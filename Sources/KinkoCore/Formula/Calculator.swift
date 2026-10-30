import Foundation

/// 表の数式を計算する。参照先のセルを先に計算し、結果を覚えておく。
/// 表を変えたら、このオブジェクトを作り直す（どのセルがどこから参照されているかは追わず、毎回すべて計算し直す。小さな表には十分）
public final class Calculator {
  /// 数式から数式へたどれる深さの上限。深すぎる再帰でスタックがあふれてアプリが落ちるのを防ぐ
  static let maxDepth = 400

  private let workbook: Workbook
  let today: Date
  private var cache: [Key: CellValue] = [:]
  private var evaluating: Set<Key> = []

  private struct Key: Hashable {
    var sheet: Int
    var address: CellAddress
  }

  public init(workbook: Workbook, today: Date = Date()) {
    self.workbook = workbook
    self.today = today
  }

  /// セルの値。数式なら計算した結果
  public func value(sheet: Int, at address: CellAddress) -> CellValue {
    let key = Key(sheet: sheet, address: address)
    if let cached = cache[key] { return cached }
    guard workbook.sheets.indices.contains(sheet) else { return .error(.ref) }
    let input = workbook.sheets[sheet][address]
    guard CellInput.isFormula(input) else { return CellInput.literal(input) }
    // 計算中のセルにまた来たら、どこかで自分自身を参照している
    guard !evaluating.contains(key), evaluating.count < Self.maxDepth else { return .error(.circular) }
    evaluating.insert(key)
    defer { evaluating.remove(key) }
    var result = Formula.parse(input).map { scalar(evaluate($0, sheet: sheet)) } ?? .error(.name)
    // 空のセルだけを参照する数式は 0 と表示する（Excel と同じ）
    if result == .empty { result = .number(0) }
    cache[key] = result
    return result
  }

  /// シートの中身のあるセルをすべて計算する。上の行から順に計算するので、下へ続く参照の連鎖でも深くならない
  public func values(sheet: Int) -> [CellAddress: CellValue] {
    guard workbook.sheets.indices.contains(sheet) else { return [:] }
    var values: [CellAddress: CellValue] = [:]
    for address in workbook.sheets[sheet].cells.keys.sorted() {
      values[address] = value(sheet: sheet, at: address)
    }
    return values
  }

  // MARK: - 式の計算

  /// 式の結果。範囲は SUM などの関数に渡すまで、範囲のまま持つ
  enum Operand {
    case value(CellValue)
    case range(sheet: Int, CellRange)
  }

  func evaluate(_ expr: FormulaExpr, sheet: Int) -> Operand {
    switch expr {
    case .literal(let value):
      return .value(value)
    case .missing:
      return .value(.empty)
    case .reference(let reference):
      guard let target = reference.sheet.map({ workbook.sheetIndex(named: $0) }) ?? sheet else {
        return .value(.error(.ref))
      }
      if reference.end == nil, let row = reference.start.row {
        return .value(value(sheet: target, at: CellAddress(row: row, column: reference.start.column)))
      }
      return .range(sheet: target, reference.range)
    case .unary(let op, let operand):
      let value = scalar(evaluate(operand, sheet: sheet))
      return .value(op == "-" ? arithmetic(value, .number(-1), *) : value)
    case .percent(let operand):
      return .value(arithmetic(scalar(evaluate(operand, sheet: sheet)), .number(100), /))
    case .binary(let op, let lhs, let rhs):
      let a = scalar(evaluate(lhs, sheet: sheet))
      let b = scalar(evaluate(rhs, sheet: sheet))
      return .value(binary(op, a, b))
    case .call(let name, let arguments):
      return .value(call(name, arguments, sheet: sheet))
    }
  }

  /// 1 つの値にする。範囲を値として使うのは、1 つのセルの範囲だけ
  func scalar(_ operand: Operand) -> CellValue {
    switch operand {
    case .value(let value):
      return value
    case .range(let sheet, let range):
      return range.start == range.end ? value(sheet: sheet, at: range.start) : .error(.value)
    }
  }

  func binary(_ op: String, _ a: CellValue, _ b: CellValue) -> CellValue {
    switch op {
    case "+": return arithmetic(a, b, +)
    case "-": return arithmetic(a, b, -)
    case "*": return arithmetic(a, b, *)
    case "/":
      if case .success = number(a), case .success(0) = number(b) { return .error(.div0) }
      return arithmetic(a, b, /)
    case "^": return arithmetic(a, b, pow)
    case "&":
      switch (text(a), text(b)) {
      case (.success(let x), .success(let y)): return .text(x + y)
      case (.failure(let error), _), (_, .failure(let error)): return .error(error)
      }
    default:
      if let error = error(in: a) ?? error(in: b) { return .error(error) }
      let order = compare(a, b)
      switch op {
      case "=": return .bool(order == .orderedSame)
      case "<>": return .bool(order != .orderedSame)
      case "<": return .bool(order == .orderedAscending)
      case ">": return .bool(order == .orderedDescending)
      case "<=": return .bool(order != .orderedDescending)
      case ">=": return .bool(order != .orderedAscending)
      default: return .error(.value)
      }
    }
  }

  func arithmetic(_ a: CellValue, _ b: CellValue, _ operation: (Double, Double) -> Double) -> CellValue {
    switch (number(a), number(b)) {
    case (.success(let x), .success(let y)):
      let result = operation(x, y)
      return Self.checked(result)
    case (.failure(let error), _), (_, .failure(let error)):
      return .error(error)
    }
  }

  // MARK: - 型の変換（Excel と同じ決まり）

  func error(in value: CellValue) -> CellError? {
    if case .error(let error) = value { error } else { nil }
  }

  /// 空は 0、TRUE は 1、数に見える文字列は数。それ以外の文字列は #VALUE!
  func number(_ value: CellValue) -> Result<Double, CellError> {
    switch value {
    case .empty: .success(0)
    case .number(let number): .success(number)
    case .bool(let bool): .success(bool ? 1 : 0)
    case .text(let text): CellInput.number(text.trimmingCharacters(in: .whitespaces)).map(Result.success) ?? .failure(.value)
    case .error(let error): .failure(error)
    }
  }

  func text(_ value: CellValue) -> Result<String, CellError> {
    if case .error(let error) = value { return .failure(error) }
    return .success(value.displayText)
  }

  func bool(_ value: CellValue) -> Result<Bool, CellError> {
    switch value {
    case .empty: .success(false)
    case .number(let number): .success(number != 0)
    case .bool(let bool): .success(bool)
    case .text(let text):
      switch text.uppercased() {
      case "TRUE": .success(true)
      case "FALSE": .success(false)
      default: .failure(.value)
      }
    case .error(let error): .failure(error)
    }
  }

  /// 比べる順番：数 < 文字列 < 真偽値。文字列は大文字・小文字を区別しない。空は相手の型の「空」（0、""、FALSE）として比べる
  func compare(_ a: CellValue, _ b: CellValue) -> ComparisonResult {
    func rank(_ value: CellValue) -> Int {
      switch value {
      case .number: 0
      case .text: 1
      case .bool: 2
      default: 0
      }
    }
    var a = a, b = b
    if a == .empty { a = Self.emptyLike(b) }
    if b == .empty { b = Self.emptyLike(a) }
    switch (a, b) {
    case (.number(let x), .number(let y)): return x < y ? .orderedAscending : x > y ? .orderedDescending : .orderedSame
    case (.text(let x), .text(let y)): return x.caseInsensitiveCompare(y)
    case (.bool(let x), .bool(let y)): return x == y ? .orderedSame : (!x ? .orderedAscending : .orderedDescending)
    default: return rank(a) < rank(b) ? .orderedAscending : .orderedDescending
    }
  }

  static func emptyLike(_ value: CellValue) -> CellValue {
    switch value {
    case .text: .text("")
    case .bool: .bool(false)
    default: .number(0)
    }
  }

  // MARK: - 範囲

  /// 範囲の中の、中身のあるセル（左上から順）。列全体のような大きな範囲でも、中身のあるセルだけを見る
  func cells(in range: CellRange, sheet: Int) -> [(CellAddress, CellValue)] {
    guard workbook.sheets.indices.contains(sheet) else { return [] }
    let stored = workbook.sheets[sheet].cells
    let addresses: [CellAddress]
    if range.rowCount * range.columnCount <= stored.count {
      addresses = range.rows.flatMap { row in range.columns.map { CellAddress(row: row, column: $0) } }
        .filter { stored[$0] != nil }
    } else {
      addresses = stored.keys.filter(range.contains).sorted()
    }
    return addresses.map { ($0, value(sheet: sheet, at: $0)) }
  }

  /// 引数を値の並びにする。範囲は中身のあるセルの値に広げる。
  /// fromRange は範囲から来た値か（SUM などは範囲の中の文字列を無視するが、直接書いた文字列は数に直す）
  func flatten(_ arguments: [FormulaExpr], sheet: Int) -> [(value: CellValue, fromRange: Bool)] {
    arguments.flatMap { argument -> [(value: CellValue, fromRange: Bool)] in
      switch evaluate(argument, sheet: sheet) {
      case .value(let value): [(value, false)]
      case .range(let target, let range): cells(in: range, sheet: target).map { ($0.1, true) }
      }
    }
  }

  /// SUM・AVERAGE・MIN・MAX などで数えるもの
  func numbers(_ arguments: [FormulaExpr], sheet: Int) -> Result<[Double], CellError> {
    var numbers: [Double] = []
    for (value, fromRange) in flatten(arguments, sheet: sheet) {
      switch value {
      case .number(let number): numbers.append(number)
      case .error(let error): return .failure(error)
      case .empty: continue
      case .text, .bool:
        if fromRange { continue }
        switch number(value) {
        case .success(let number): numbers.append(number)
        case .failure(let error): return .failure(error)
        }
      }
    }
    return .success(numbers)
  }
}
