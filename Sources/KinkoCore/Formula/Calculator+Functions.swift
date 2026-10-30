import Foundation

/// 表の関数（SUM・IF・VLOOKUP など）
extension Calculator {
  func call(_ name: String, _ arguments: [FormulaExpr], sheet: Int) -> CellValue {
    func argument(_ index: Int) -> CellValue {
      index < arguments.count ? scalar(evaluate(arguments[index], sheet: sheet)) : .empty
    }
    func numberArgument(_ index: Int, default fallback: Double? = nil) -> Result<Double, CellError> {
      if index >= arguments.count || arguments[index] == .missing {
        return fallback.map(Result.success) ?? .failure(.value)
      }
      return number(argument(index))
    }
    func aggregate(_ body: ([Double]) -> CellValue) -> CellValue {
      switch numbers(arguments, sheet: sheet) {
      case .success(let numbers): body(numbers)
      case .failure(let error): .error(error)
      }
    }
    func requires(_ counts: ClosedRange<Int>, _ body: () -> CellValue) -> CellValue {
      counts.contains(arguments.count) ? body() : .error(.value)
    }
    func math(_ body: (Double) -> Double) -> CellValue {
      requires(1...1) {
        switch numberArgument(0) {
        case .success(let x): Self.checked(body(x))
        case .failure(let error): .error(error)
        }
      }
    }
    func textFunction(_ body: (String) -> CellValue) -> CellValue {
      switch text(argument(0)) {
      case .success(let text): body(text)
      case .failure(let error): .error(error)
      }
    }

    switch name {
    case "SUM":
      return aggregate { .number($0.reduce(0, +)) }
    case "PRODUCT":
      return aggregate { .number($0.isEmpty ? 0 : $0.reduce(1, *)) }
    case "AVERAGE":
      return aggregate { $0.isEmpty ? .error(.div0) : .number($0.reduce(0, +) / Double($0.count)) }
    case "MIN":
      return aggregate { .number($0.min() ?? 0) }
    case "MAX":
      return aggregate { .number($0.max() ?? 0) }
    case "COUNT":
      return .number(Double(flatten(arguments, sheet: sheet).filter { value, fromRange in
        if case .number = value { return true }
        return !fromRange && (try? number(value).get()) != nil && value != .empty
      }.count))
    case "COUNTA":
      return .number(Double(flatten(arguments, sheet: sheet).filter { $0.value != .empty }.count))
    case "COUNTBLANK":
      guard arguments.count == 1, case .range(let target, let range) = evaluate(arguments[0], sheet: sheet) else {
        return .error(.value)
      }
      let filled = cells(in: range, sheet: target).filter { $0.1 != .empty && $0.1 != .text("") }.count
      return .number(Double(range.rowCount * range.columnCount - filled))

    case "IF":
      return requires(1...3) {
        switch bool(argument(0)) {
        case .success(true): arguments.count > 1 && arguments[1] != .missing ? argument(1) : .bool(true)
        case .success(false): arguments.count > 2 ? argument(2) : .bool(false)
        case .failure(let error): .error(error)
        }
      }
    case "IFERROR":
      return requires(2...2) {
        if case .error = argument(0) { return argument(1) }
        return argument(0)
      }
    case "AND", "OR":
      var result = name == "AND"
      var found = false
      for (value, fromRange) in flatten(arguments, sheet: sheet) {
        if fromRange, case .text = value { continue }
        if value == .empty { continue }
        switch bool(value) {
        case .success(let bool):
          found = true
          result = name == "AND" ? result && bool : result || bool
        case .failure(let error):
          return .error(error)
        }
      }
      return found ? .bool(result) : .error(.value)
    case "NOT":
      return requires(1...1) {
        switch bool(argument(0)) {
        case .success(let bool): .bool(!bool)
        case .failure(let error): .error(error)
        }
      }

    case "ROUND", "ROUNDUP", "ROUNDDOWN":
      return requires(1...2) {
        switch (numberArgument(0), numberArgument(1, default: 0)) {
        case (.success(let x), .success(let digits)):
          let rule: FloatingPointRoundingRule =
            switch name {
            case "ROUNDUP": .awayFromZero
            case "ROUNDDOWN": .towardZero
            default: .toNearestOrAwayFromZero
            }
          return .number(Self.round(x, digits: Int(digits), rule: rule))
        case (.failure(let error), _), (_, .failure(let error)):
          return .error(error)
        }
      }
    case "INT": return math { $0.rounded(.down) }
    case "ABS": return math { abs($0) }
    case "SQRT": return math { $0 < 0 ? .nan : $0.squareRoot() }
    case "PI": return requires(0...0) { .number(.pi) }
    case "MOD", "POWER":
      return requires(2...2) {
        switch (numberArgument(0), numberArgument(1)) {
        case (.success(let x), .success(let y)):
          if name == "POWER" { return Self.checked(pow(x, y)) }
          // 割る数と同じ符号になる（Excel と同じ。Swift の % とは違う）
          return y == 0 ? .error(.div0) : .number(x - y * (x / y).rounded(.down))
        case (.failure(let error), _), (_, .failure(let error)):
          return .error(error)
        }
      }

    case "CONCAT", "CONCATENATE":
      var result = ""
      for (value, _) in flatten(arguments, sheet: sheet) {
        switch text(value) {
        case .success(let text): result += text
        case .failure(let error): return .error(error)
        }
      }
      return .text(result)
    case "LEN": return requires(1...1) { textFunction { .number(Double($0.count)) } }
    case "UPPER": return requires(1...1) { textFunction { .text($0.uppercased()) } }
    case "LOWER": return requires(1...1) { textFunction { .text($0.lowercased()) } }
    case "TRIM":
      // 前後の空白を除き、間の連続した空白を 1 つにする
      return requires(1...1) { textFunction { .text($0.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")) } }
    case "LEFT", "RIGHT":
      return requires(1...2) {
        switch (text(argument(0)), numberArgument(1, default: 1)) {
        case (.success(let text), .success(let count)):
          guard count >= 0 else { return .error(.value) }
          let n = min(Int(count), text.count)
          return .text(String(name == "LEFT" ? text.prefix(n) : text.suffix(n)))
        case (.failure(let error), _), (_, .failure(let error)):
          return .error(error)
        }
      }
    case "MID":
      return requires(3...3) {
        switch (text(argument(0)), numberArgument(1), numberArgument(2)) {
        case (.success(let text), .success(let start), .success(let count)):
          guard start >= 1, count >= 0 else { return .error(.value) }
          return .text(String(text.dropFirst(Int(start) - 1).prefix(Int(count))))
        case (.failure(let error), _, _), (_, .failure(let error), _), (_, _, .failure(let error)):
          return .error(error)
        }
      }

    case "SUMIF", "COUNTIF", "AVERAGEIF":
      return conditional(name, arguments, sheet: sheet)
    case "VLOOKUP":
      return vlookup(arguments, sheet: sheet)
    case "TODAY":
      // Kinko には日付の型がないので、日付の文字列を返す
      return requires(0...0) { .text(Self.dateText(today)) }
    default:
      return .error(.name)
    }
  }

  static func checked(_ number: Double) -> CellValue {
    number.isFinite ? .number(number) : .error(.num)
  }

  /// 桁をそろえて丸める。2.675 は 2 進数では 2.67499… なので、そのまま丸めると 2.67 になる。
  /// Excel と同じく有効数字 15 桁に直してから丸めて 2.68 にする
  static func round(_ x: Double, digits: Int, rule: FloatingPointRoundingRule) -> Double {
    let digits = max(-15, min(15, digits))
    let scale = pow(10, Double(abs(digits)))
    let scaled = digits >= 0 ? x * scale : x / scale
    let cleaned = Double(String(format: "%.15g", scaled)) ?? scaled
    let rounded = cleaned.rounded(rule)
    return digits >= 0 ? rounded / scale : rounded * scale
  }

  static func dateText(_ date: Date) -> String {
    let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d/%02d/%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }

  /// SUMIF(範囲, 条件, [合計範囲])、COUNTIF(範囲, 条件)、AVERAGEIF(範囲, 条件, [平均範囲])
  private func conditional(_ name: String, _ arguments: [FormulaExpr], sheet: Int) -> CellValue {
    let maxArguments = name == "COUNTIF" ? 2 : 3
    guard (2...maxArguments).contains(arguments.count),
      case .range(let target, let range) = evaluate(arguments[0], sheet: sheet)
    else { return .error(.value) }
    let criteria = scalar(evaluate(arguments[1], sheet: sheet))
    if case .error(let error) = criteria { return .error(error) }
    let matches = Self.matcher(for: criteria)

    if name == "COUNTIF" {
      let filled = cells(in: range, sheet: target)
      var count = filled.filter { matches($0.1) }.count
      // 空のセルは並びに入っていないので、空を数える条件ならまとめて足す
      if matches(.empty) { count += range.rowCount * range.columnCount - filled.count }
      return .number(Double(count))
    }

    var sumTarget = target
    var origin = range.start
    if arguments.count == 3 {
      guard case .range(let other, let sumRange) = evaluate(arguments[2], sheet: sheet) else { return .error(.value) }
      sumTarget = other
      origin = sumRange.start
    }
    var total = 0.0
    var count = 0
    for (address, value) in cells(in: range, sheet: target) where matches(value) {
      let offset = CellAddress(
        row: origin.row + address.row - range.start.row, column: origin.column + address.column - range.start.column)
      switch self.value(sheet: sumTarget, at: offset) {
      case .number(let number):
        total += number
        count += 1
      case .error(let error):
        return .error(error)
      default:
        continue
      }
    }
    if name == "AVERAGEIF" { return count == 0 ? .error(.div0) : .number(total / Double(count)) }
    return .number(total)
  }

  /// COUNTIF などの条件。">=10" "<>済" "りんご" "*店" のように書ける。* と ? はワイルドカード（~ で打ち消す）
  static func matcher(for criteria: CellValue) -> (CellValue) -> Bool {
    guard case .text(let text) = criteria else {
      return { value in
        switch (criteria, value) {
        case (.number(let x), .number(let y)): x == y
        case (.number(let x), .text(let y)): CellInput.number(y) == x
        case (.bool(let x), .bool(let y)): x == y
        default: false
        }
      }
    }
    var op = "="
    var operand = Substring(text)
    for candidate in ["<=", ">=", "<>", "<", ">", "="] where operand.hasPrefix(candidate) {
      op = candidate
      operand = operand.dropFirst(candidate.count)
      break
    }
    let operandText = String(operand)
    if let number = CellInput.number(operandText) {
      return { value in
        guard case .number(let x) = value else {
          if op == "<>" { return true }
          if op == "=", case .text(let text) = value { return CellInput.number(text) == number }
          return false
        }
        switch op {
        case "<": return x < number
        case ">": return x > number
        case "<=": return x <= number
        case ">=": return x >= number
        case "<>": return x != number
        default: return x == number
        }
      }
    }
    if operandText.isEmpty {
      // "=" は空のセル、"<>" は空でないセル
      return { value in
        let isEmpty = value == .empty || value == .text("")
        return op == "<>" ? !isEmpty : (op == "=" ? isEmpty : false)
      }
    }
    let pattern = wildcardPattern(operandText)
    return { value in
      guard value != .empty else { return op == "<>" }
      let cellText = value.displayText
      switch op {
      case "=", "<>":
        let isMatch = pattern.firstMatch(in: cellText, range: NSRange(cellText.startIndex..., in: cellText)) != nil
        return op == "=" ? isMatch : !isMatch
      default:
        guard case .text = value else { return false }
        let order = cellText.caseInsensitiveCompare(operandText)
        switch op {
        case "<": return order == .orderedAscending
        case ">": return order == .orderedDescending
        case "<=": return order != .orderedDescending
        default: return order != .orderedAscending
        }
      }
    }
  }

  private static func wildcardPattern(_ text: String) -> NSRegularExpression {
    var pattern = "^"
    var escaping = false
    for char in text {
      if escaping {
        pattern += NSRegularExpression.escapedPattern(for: String(char))
        escaping = false
      } else if char == "~" {
        escaping = true
      } else if char == "*" {
        pattern += ".*"
      } else if char == "?" {
        pattern += "."
      } else {
        pattern += NSRegularExpression.escapedPattern(for: String(char))
      }
    }
    pattern += "$"
    // 自分で組み立てた、エスケープ済みのパターンなので失敗しない
    return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
  }

  /// VLOOKUP(検索値, 表, 列番号, [近似一致 = TRUE])。近似一致は、1 列目が昇順に並んでいる前提で、検索値以下の最後の行を使う
  private func vlookup(_ arguments: [FormulaExpr], sheet: Int) -> CellValue {
    guard (3...4).contains(arguments.count),
      case .range(let target, let table) = evaluate(arguments[1], sheet: sheet)
    else { return .error(.value) }
    let key = scalar(evaluate(arguments[0], sheet: sheet))
    if case .error(let error) = key { return .error(error) }
    guard case .success(let columnNumber) = number(scalar(evaluate(arguments[2], sheet: sheet))) else {
      return .error(.value)
    }
    let approximate: Bool
    if arguments.count == 4 {
      guard case .success(let flag) = bool(scalar(evaluate(arguments[3], sheet: sheet))) else { return .error(.value) }
      approximate = flag
    } else {
      approximate = true
    }
    let column = Int(columnNumber)
    guard column >= 1 else { return .error(.value) }
    guard column <= table.columnCount else { return .error(.ref) }

    let firstColumn = CellRange(table.start, CellAddress(row: table.end.row, column: table.start.column))
    var found: Int?
    for (address, candidate) in cells(in: firstColumn, sheet: target) {
      if case .error = candidate { continue }
      let order = compare(candidate, key)
      if approximate {
        // 型が違うものは飛ばす（Excel と同じ）
        guard Self.sameKind(candidate, key) else { continue }
        if order == .orderedDescending { break }
        found = address.row
      } else if order == .orderedSame, Self.sameKind(candidate, key) {
        found = address.row
        break
      }
    }
    guard let row = found else { return .error(.na) }
    let result = value(sheet: target, at: CellAddress(row: row, column: table.start.column + column - 1))
    return result == .empty ? .number(0) : result
  }

  private static func sameKind(_ a: CellValue, _ b: CellValue) -> Bool {
    switch (a, b) {
    case (.number, .number), (.text, .text), (.bool, .bool): true
    default: false
    }
  }
}
