import Foundation

struct FormulaToken: Equatable {
  enum Kind: Equatable {
    case number(Double)
    case string(String)
    case reference(FormulaReference)
    /// 関数名（大文字）。直後に "(" が続く
    case function(String)
    /// TRUE・FALSE 以外の名前（Excel の「名前の定義」には対応しないので #NAME? になる）
    case name(String)
    case bool(Bool)
    case error(CellError)
    case op(String)
    case openParen, closeParen, comma
  }

  var kind: Kind
  /// 数式（先頭の "=" を除く）の中の位置。文字（Character）単位
  var range: Range<Int>
}

struct FormulaSyntaxError: Error {}

struct FormulaLexer {
  private let source: [Character]
  private var index = 0

  init(_ source: [Character]) {
    self.source = source
  }

  mutating func tokens() throws(FormulaSyntaxError) -> [FormulaToken] {
    var tokens: [FormulaToken] = []
    while index < source.count {
      let char = source[index]
      if char.isWhitespace {
        index += 1
        continue
      }
      let start = index
      let kind = try nextKind(char)
      tokens.append(FormulaToken(kind: kind, range: start..<index))
    }
    return tokens
  }

  private func peek(_ offset: Int = 0) -> Character? {
    index + offset < source.count ? source[index + offset] : nil
  }

  private mutating func nextKind(_ char: Character) throws(FormulaSyntaxError) -> FormulaToken.Kind {
    switch char {
    case "(": index += 1; return .openParen
    case ")": index += 1; return .closeParen
    case ",": index += 1; return .comma
    case "+", "-", "*", "/", "^", "&", "=", "%":
      index += 1
      return .op(String(char))
    case "<", ">":
      index += 1
      if let next = peek(), next == "=" || (char == "<" && next == ">") {
        index += 1
        return .op(String(char) + String(next))
      }
      return .op(String(char))
    case "\"":
      return .string(try readString())
    case "#":
      // 長いものから試す（#N/A と #NAME? など）
      for error in CellError.allCases.sorted(by: { $0.rawValue.count > $1.rawValue.count }) {
        let text = Array(error.rawValue)
        if index + text.count <= source.count, String(source[index..<index + text.count]).uppercased() == error.rawValue {
          index += text.count
          return .error(error)
        }
      }
      throw FormulaSyntaxError()
    default:
      if char.isNumber && char.isASCII || char == "." { return .number(try readNumber()) }
      if let reference = readReference() { return .reference(reference) }
      return try readName()
    }
  }

  private mutating func readString() throws(FormulaSyntaxError) -> String {
    index += 1
    var text = ""
    while let char = peek() {
      index += 1
      if char == "\"" {
        // "" は " 1 文字
        if peek() == "\"" {
          text.append("\"")
          index += 1
        } else {
          return text
        }
      } else {
        text.append(char)
      }
    }
    throw FormulaSyntaxError()
  }

  private mutating func readNumber() throws(FormulaSyntaxError) -> Double {
    let start = index
    while let char = peek(), char.isASCII, char.isNumber || char == "." { index += 1 }
    // 指数（1e3、2.5E-2）。e の後に数字が続くときだけ
    if let e = peek(), e == "e" || e == "E" {
      var offset = 1
      if let sign = peek(1), sign == "+" || sign == "-" { offset = 2 }
      if let digit = peek(offset), digit.isASCII, digit.isNumber {
        index += offset
        while let char = peek(), char.isASCII, char.isNumber { index += 1 }
      }
    }
    guard let number = Double(String(source[start..<index])), number.isFinite else { throw FormulaSyntaxError() }
    return number
  }

  /// 関数名・名前・シート名に使える文字
  private static func isNameCharacter(_ char: Character) -> Bool {
    char.isLetter || char.isNumber || char == "_" || char == "."
  }

  /// 参照として読めれば読み進める。読めなければ位置を戻して nil
  private mutating func readReference() -> FormulaReference? {
    let start = index
    var sheet: String?
    // シート名：'…'! か 名前!
    if peek() == "'" {
      index += 1
      var name = ""
      while let char = peek() {
        index += 1
        if char == "'" {
          if peek() == "'" {
            name.append("'")
            index += 1
          } else {
            break
          }
        } else {
          name.append(char)
        }
      }
      guard peek() == "!" else {
        index = start
        return nil
      }
      index += 1
      sheet = name
    } else {
      var end = index
      while end < source.count, Self.isNameCharacter(source[end]) { end += 1 }
      if end > index, end < source.count, source[end] == "!" {
        sheet = String(source[index..<end])
        index = end + 1
      }
    }

    if let first = readCorner(allowsColumnOnly: true) {
      if first.row == nil {
        // 列全体（A:C）。「:」と 2 つ目の列が必ず続く
        if peek() == ":" {
          index += 1
          if let second = readCorner(allowsColumnOnly: true), second.row == nil, !continuesName() {
            return FormulaReference(sheet: sheet, start: first, end: second)
          }
        }
      } else if !continuesName() {
        let beforeColon = index
        if peek() == ":" {
          index += 1
          if let second = readCorner(allowsColumnOnly: false), !continuesName() {
            return FormulaReference(sheet: sheet, start: first, end: second)
          }
          index = beforeColon
        }
        return FormulaReference(sheet: sheet, start: first)
      }
    }
    // 参照ではなかった。関数名や名前として読み直す（シート名の後に参照が続かないなら、そこで構文の誤りになる）
    index = start
    return nil
  }

  /// 参照の直後に名前の文字や "(" が続くなら、参照ではなく関数名などの一部（LOG10( など）
  private func continuesName() -> Bool {
    guard let next = peek() else { return false }
    return Self.isNameCharacter(next) || next == "(" || next == "!"
  }

  /// $A$1 や A（列だけ）を読む
  private mutating func readCorner(allowsColumnOnly: Bool) -> FormulaReference.Corner? {
    let start = index
    let columnAbsolute = peek() == "$"
    if columnAbsolute { index += 1 }
    var letters = ""
    while let char = peek(), char.isASCII, char.isLetter, letters.count < 4 {
      letters.append(char)
      index += 1
    }
    guard let column = CellAddress.columnIndex(letters) else {
      index = start
      return nil
    }
    let rowAbsolute = peek() == "$"
    if rowAbsolute { index += 1 }
    var digits = ""
    while let char = peek(), char.isASCII, char.isNumber {
      digits.append(char)
      index += 1
    }
    if digits.isEmpty {
      guard allowsColumnOnly, !rowAbsolute else {
        index = start
        return nil
      }
      return FormulaReference.Corner(row: nil, column: column, isColumnAbsolute: columnAbsolute)
    }
    guard digits.first != "0", let row = Int(digits), row <= CellAddress.maxRows else {
      index = start
      return nil
    }
    return FormulaReference.Corner(
      row: row - 1, column: column, isRowAbsolute: rowAbsolute, isColumnAbsolute: columnAbsolute)
  }

  private mutating func readName() throws(FormulaSyntaxError) -> FormulaToken.Kind {
    let start = index
    while let char = peek(), Self.isNameCharacter(char) { index += 1 }
    guard index > start else { throw FormulaSyntaxError() }
    var name = String(source[start..<index]).uppercased()
    if peek() == "(" {
      // Excel のファイルでは新しい関数に付いている印
      for prefix in ["_XLFN.", "_XLWS."] where name.hasPrefix(prefix) { name.removeFirst(prefix.count) }
      return .function(name)
    }
    switch name {
    case "TRUE": return .bool(true)
    case "FALSE": return .bool(false)
    default: return .name(name)
    }
  }
}
