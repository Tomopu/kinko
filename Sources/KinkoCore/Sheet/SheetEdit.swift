import Foundation

/// 行・列・セルの挿入と削除。セルを動かし、動いたセルを指す数式の参照も書き換える（Excel と同じ）
extension Workbook {
  public enum Shift: Sendable {
    /// 挿入：下へずらす／削除：上へ詰める
    case vertical
    /// 挿入：右へずらす／削除：左へ詰める
    case horizontal
  }

  public mutating func insertRows(at row: Int, count: Int, inSheet sheet: Int) {
    apply(AxisEdit(axis: .row, at: row, count: count, span: nil), inSheet: sheet)
  }

  public mutating func deleteRows(_ rows: ClosedRange<Int>, inSheet sheet: Int) {
    apply(AxisEdit(axis: .row, at: rows.lowerBound, count: -rows.count, span: nil), inSheet: sheet)
  }

  public mutating func insertColumns(at column: Int, count: Int, inSheet sheet: Int) {
    apply(AxisEdit(axis: .column, at: column, count: count, span: nil), inSheet: sheet)
  }

  public mutating func deleteColumns(_ columns: ClosedRange<Int>, inSheet sheet: Int) {
    apply(AxisEdit(axis: .column, at: columns.lowerBound, count: -columns.count, span: nil), inSheet: sheet)
  }

  /// range と同じ大きさの空きを作り、そこにあったセルを下（または右）へずらす
  public mutating func insertCells(_ range: CellRange, shift: Shift, inSheet sheet: Int) {
    switch shift {
    case .vertical: apply(AxisEdit(axis: .row, at: range.start.row, count: range.rowCount, span: range.columns), inSheet: sheet)
    case .horizontal: apply(AxisEdit(axis: .column, at: range.start.column, count: range.columnCount, span: range.rows), inSheet: sheet)
    }
  }

  /// range のセルを消し、下（または右）のセルを詰める
  public mutating func deleteCells(_ range: CellRange, shift: Shift, inSheet sheet: Int) {
    switch shift {
    case .vertical: apply(AxisEdit(axis: .row, at: range.start.row, count: -range.rowCount, span: range.columns), inSheet: sheet)
    case .horizontal: apply(AxisEdit(axis: .column, at: range.start.column, count: -range.columnCount, span: range.rows), inSheet: sheet)
    }
  }

  // MARK: - 並べ替え

  /// range の行を、column 列の値で並べ替える。行ごと（書式も）動き、数式の相対参照は動いた行数だけずらす（Excel と同じ）。
  /// 空のセルは昇順でも降順でも最後にする
  public mutating func sortRows(_ range: CellRange, by column: Int, ascending: Bool, inSheet sheet: Int) {
    guard sheets.indices.contains(sheet), range.rowCount > 1 else { return }
    let calculator = Calculator(workbook: self)
    let keys = range.rows.map { row in (row: row, value: calculator.value(sheet: sheet, at: CellAddress(row: row, column: column))) }
    let order = keys.enumerated().sorted { a, b in
      let x = a.element.value, y = b.element.value
      if x == .empty || y == .empty {
        return x != .empty || (x == y && a.offset < b.offset)
      }
      let result = Self.sortOrder(x, y)
      if result == .orderedSame { return a.offset < b.offset }
      return ascending ? result == .orderedAscending : result == .orderedDescending
    }.map(\.element.row)

    var cells = sheets[sheet].cells
    var styles = sheets[sheet].styles
    for (index, sourceRow) in order.enumerated() {
      let targetRow = range.start.row + index
      for column in range.columns {
        let source = CellAddress(row: sourceRow, column: column)
        let target = CellAddress(row: targetRow, column: column)
        let input = sheets[sheet][source]
        cells[target] =
          input.isEmpty ? nil : (CellInput.isFormula(input) ? Formula.shifted(input, rowOffset: targetRow - sourceRow, columnOffset: 0) : input)
        styles[target] = sheets[sheet].styles[source]
      }
    }
    sheets[sheet].replaceCells(cells)
    sheets[sheet].replaceStyles(styles)
  }

  /// 並べ替えの順：数 < 文字列 < 真偽値 < エラー。文字列は大文字・小文字を区別せず、数字の部分は数として比べる
  private static func sortOrder(_ a: CellValue, _ b: CellValue) -> ComparisonResult {
    func rank(_ value: CellValue) -> Int {
      switch value {
      case .number: 0
      case .text: 1
      case .bool: 2
      default: 3
      }
    }
    switch (a, b) {
    case (.number(let x), .number(let y)): return x < y ? .orderedAscending : (x > y ? .orderedDescending : .orderedSame)
    case (.text(let x), .text(let y)): return x.localizedStandardCompare(y)
    case (.bool(let x), .bool(let y)): return x == y ? .orderedSame : (x ? .orderedDescending : .orderedAscending)
    default:
      let (x, y) = (rank(a), rank(b))
      return x < y ? .orderedAscending : (x > y ? .orderedDescending : .orderedSame)
    }
  }

  // MARK: - シート

  public mutating func addSheet() -> Int {
    sheets.append(Sheet(name: newSheetName()))
    return sheets.count - 1
  }

  /// シート名を変え、そのシートを指す数式も新しい名前に書き換える
  public mutating func renameSheet(_ index: Int, to name: String) throws(WorkspaceError) {
    let name = name.trimmingCharacters(in: .whitespaces)
    // Excel と同じ制限。書き出したファイルを Excel で開けるように
    guard !name.isEmpty, name.count <= 31, !name.contains(where: { "[]:*?/\\".contains($0) }),
      !name.hasPrefix("'"), !name.hasSuffix("'")
    else { throw .invalidSheetName }
    if let existing = sheetIndex(named: name), existing != index { throw .duplicateName(name) }
    let old = sheets[index].name
    rewriteFormulas { reference, _ in
      guard let sheet = reference.sheet, sheet.caseInsensitiveCompare(old) == .orderedSame else { return reference }
      var reference = reference
      reference.sheet = name
      return reference
    }
    sheets[index].name = name
  }

  /// シートを消す。そのシートを指していた数式は #REF! になる。最後の 1 枚は消せない
  public mutating func removeSheet(_ index: Int) {
    guard sheets.count > 1 else { return }
    let name = sheets[index].name
    sheets.remove(at: index)
    rewriteFormulas { reference, _ in
      guard let sheet = reference.sheet, sheet.caseInsensitiveCompare(name) == .orderedSame else { return reference }
      return nil
    }
  }

  // MARK: - 内部

  /// すべてのシートの数式の参照を書き換える。transform にはシートの番号も渡す
  private mutating func rewriteFormulas(_ transform: (FormulaReference, Int) -> FormulaReference?) {
    for index in sheets.indices {
      let cells = sheets[index].cells
      var changed = cells
      for (address, input) in cells where CellInput.isFormula(input) {
        changed[address] = Formula.rewritingReferences(input) { transform($0, index) }
      }
      if changed != cells { sheets[index].replaceCells(changed) }
    }
  }

  private mutating func apply(_ edit: AxisEdit, inSheet sheet: Int) {
    guard sheets.indices.contains(sheet), edit.count != 0 else { return }
    let name = sheets[sheet].name
    // 数式の中の参照を書き換えてから、セルの位置を動かす
    rewriteFormulas { reference, index in
      let targetsEditedSheet =
        reference.sheet.map { $0.caseInsensitiveCompare(name) == .orderedSame } ?? (index == sheet)
      return targetsEditedSheet ? edit.transform(reference) : reference
    }
    var moved: [CellAddress: String] = [:]
    for (address, input) in sheets[sheet].cells {
      if let target = edit.map(address) { moved[target] = input }
    }
    sheets[sheet].replaceCells(moved)
    // 書式もセルと一緒に動く
    var movedStyles: [CellAddress: CellStyle] = [:]
    for (address, style) in sheets[sheet].styles {
      if let target = edit.map(address) { movedStyles[target] = style }
    }
    sheets[sheet].replaceStyles(movedStyles)
    // 列の幅と行の高さは、列・行をまるごと挿入・削除したときだけ一緒に動く
    if edit.span == nil {
      var sizes: [Int: Double] = [:]
      for (position, size) in edit.axis == .column ? sheets[sheet].columnWidths : sheets[sheet].rowHeights {
        if let target = edit.map(position: position) { sizes[target] = size }
      }
      if edit.axis == .column { sheets[sheet].columnWidths = sizes } else { sheets[sheet].rowHeights = sizes }
    }
  }
}

/// 1 つの軸（行か列）に沿った挿入・削除
struct AxisEdit {
  enum Axis { case row, column }

  var axis: Axis
  var at: Int
  /// 正なら挿入する数、負なら削除する数
  var count: Int
  /// もう一方の軸のうち動かす範囲（セルの挿入・削除）。nil なら行・列まるごと
  var span: ClosedRange<Int>?

  /// 軸に沿った位置の移り先。削除されたら nil
  func map(position: Int) -> Int? {
    if count > 0 { return position >= at ? position + count : position }
    let deleted = at..<(at - count)
    if position < at { return position }
    return deleted.contains(position) ? nil : position + count
  }

  private func along(_ address: CellAddress) -> Int { axis == .row ? address.row : address.column }
  private func across(_ address: CellAddress) -> Int { axis == .row ? address.column : address.row }

  /// セルの移り先。動かない範囲のセルはそのまま。削除されたか表の外へ押し出されたら nil
  func map(_ address: CellAddress) -> CellAddress? {
    if let span, !span.contains(across(address)) { return address }
    guard let position = map(position: along(address)) else { return nil }
    let moved =
      axis == .row
      ? CellAddress(row: position, column: address.column) : CellAddress(row: address.row, column: position)
    return moved.isValid ? moved : nil
  }

  /// 参照の書き換え。範囲は、間に挿入すれば広がり、一部を削除すれば縮む。全部削除されたら nil（#REF!）
  func transform(_ reference: FormulaReference) -> FormulaReference? {
    var reference = reference
    func position(_ corner: FormulaReference.Corner) -> Int? { axis == .row ? corner.row : corner.column }
    func set(_ corner: inout FormulaReference.Corner, _ value: Int) {
      if axis == .row { corner.row = value } else { corner.column = value }
    }

    // 行の操作は列全体の参照（A:A）に影響しない
    guard let start = position(reference.start) else { return reference }
    let range = reference.range
    if let span {
      // セルだけをずらすときは、参照がずらす帯の中に収まっているものだけ動かす
      let crossing = axis == .row ? range.columns : range.rows
      guard span.contains(crossing.lowerBound), span.contains(crossing.upperBound) else { return reference }
    }
    let end = reference.end.flatMap(position) ?? start
    let limit = axis == .row ? CellAddress.maxRows : CellAddress.maxColumns

    if count > 0 {
      let newStart = start >= at ? start + count : start
      let newEnd = end >= at ? end + count : end
      guard newEnd < limit else { return nil }
      set(&reference.start, newStart)
      if reference.end != nil { set(&reference.end!, newEnd) }
      return reference
    }

    let removed = -count
    let last = at + removed - 1
    if start > last {
      set(&reference.start, start - removed)
      if reference.end != nil { set(&reference.end!, end - removed) }
    } else if end >= at {
      if start >= at && end <= last { return nil }
      let newStart = start < at ? start : at
      let newEnd = end > last ? end - removed : at - 1
      set(&reference.start, newStart)
      if reference.end != nil { set(&reference.end!, newEnd) }
    }
    return reference
  }
}
