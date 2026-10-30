import Foundation

/// 数式の中のセル参照（A1、$B$2、Sheet2!A1:B3、A:A）
public struct FormulaReference: Equatable, Sendable {
  public struct Corner: Equatable, Sendable {
    /// nil なら列全体（A:A の A）
    public var row: Int?
    public var column: Int
    /// "$" が付いていて、数式を複製してもずれない
    public var isRowAbsolute = false
    public var isColumnAbsolute = false

    public init(row: Int?, column: Int, isRowAbsolute: Bool = false, isColumnAbsolute: Bool = false) {
      self.row = row
      self.column = column
      self.isRowAbsolute = isRowAbsolute
      self.isColumnAbsolute = isColumnAbsolute
    }

    var text: String {
      (isColumnAbsolute ? "$" : "") + CellAddress.columnName(column)
        + (row.map { (isRowAbsolute ? "$" : "") + String($0 + 1) } ?? "")
    }
  }

  /// 別のシートを指すときのシート名。nil なら数式のあるシート
  public var sheet: String?
  public var start: Corner
  /// 範囲なら右下の角。1 つのセルなら nil
  public var end: Corner?

  /// 指している範囲。列全体の参照は全行になる
  var range: CellRange {
    let end = end ?? start
    return CellRange(
      CellAddress(row: start.row ?? 0, column: start.column),
      CellAddress(row: end.row ?? CellAddress.maxRows - 1, column: end.column))
  }

  var text: String {
    let prefix = sheet.map { Self.quotedSheetName($0) + "!" } ?? ""
    return prefix + start.text + (end.map { ":" + $0.text } ?? "")
  }

  /// 英字で始まり英数字だけの名前はそのまま、それ以外（空白・記号を含む、セル番地に見える）は '…' で囲む
  static func quotedSheetName(_ name: String) -> String {
    let isPlain =
      name.first.map { $0.isLetter || $0 == "_" } == true
      && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
      && CellAddress(name) == nil
    return isPlain ? name : "'" + name.replacingOccurrences(of: "'", with: "''") + "'"
  }
}

/// 数式を解析した木
indirect enum FormulaExpr: Equatable {
  case literal(CellValue)
  case reference(FormulaReference)
  case unary(String, FormulaExpr)
  case binary(String, FormulaExpr, FormulaExpr)
  case percent(FormulaExpr)
  case call(String, [FormulaExpr])
  /// 省略した引数（IF(A1,,1) の 2 つ目）
  case missing
}

public enum Formula {
  /// 数式の相対参照を rowOffset 行・columnOffset 列ずらす（"$" の付いた絶対参照はずらさない）。
  /// input は "=" から始まるセルの入力。ずらした先が表の外になる参照は #REF! になる（Excel と同じ）
  public static func shifted(_ input: String, rowOffset: Int, columnOffset: Int) -> String {
    rewritingReferences(input) { reference in
      var reference = reference
      func shift(_ corner: inout FormulaReference.Corner) -> Bool {
        if !corner.isColumnAbsolute { corner.column += columnOffset }
        if let row = corner.row, !corner.isRowAbsolute { corner.row = row + rowOffset }
        return (0..<CellAddress.maxColumns).contains(corner.column)
          && (corner.row.map { (0..<CellAddress.maxRows).contains($0) } ?? true)
      }
      guard shift(&reference.start) else { return nil }
      if reference.end != nil {
        guard shift(&reference.end!) else { return nil }
      }
      return reference
    }
  }

  /// 数式の中の参照を 1 つずつ書き換える。transform が nil を返した参照は #REF! にする。
  /// 参照以外（空白・関数名・文字列）は元の書き方のまま残す。数式でない入力や読めない数式はそのまま返す
  static func rewritingReferences(_ input: String, _ transform: (FormulaReference) -> FormulaReference?) -> String {
    guard CellInput.isFormula(input) else { return input }
    let source = Array(input.dropFirst())
    var lexer = FormulaLexer(source)
    guard let tokens = try? lexer.tokens() else { return input }
    var output = "="
    var position = 0
    for token in tokens {
      guard case .reference(let reference) = token.kind else { continue }
      output += String(source[position..<token.range.lowerBound])
      output += transform(reference).map(\.text) ?? CellError.ref.rawValue
      position = token.range.upperBound
    }
    output += String(source[position...])
    return output
  }

  /// "=" から始まる入力を解析する。読めなければ nil
  static func parse(_ input: String) -> FormulaExpr? {
    guard CellInput.isFormula(input) else { return nil }
    var lexer = FormulaLexer(Array(input.dropFirst()))
    guard let tokens = try? lexer.tokens() else { return nil }
    var parser = FormulaParser(tokens: tokens)
    return try? parser.parse()
  }

  /// 数式が参照しているもの（テスト用）
  static func references(in input: String) -> [FormulaReference] {
    guard CellInput.isFormula(input) else { return [] }
    var lexer = FormulaLexer(Array(input.dropFirst()))
    guard let tokens = try? lexer.tokens() else { return [] }
    return tokens.compactMap { if case .reference(let reference) = $0.kind { reference } else { nil } }
  }
}
