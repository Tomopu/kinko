import KinkoCore

extension SheetEditorModel {
  // MARK: - 並べ替え・検索・集計

  /// 選んだ範囲の行を、入力先のセルの列で並べ替える。範囲を選んでいなければ、どこを並べ替えるか分からないので断る
  func sort(ascending: Bool) {
    guard let range = usedSelection, range.rowCount > 1 else {
      errorMessage = "並べ替える行の範囲を選んでください（見出しの行は含めないでください）。"
      return
    }
    commit { $0.sortRows(range, by: active.column, ascending: ascending, inSheet: sheetIndex) }
  }

  /// 入力先の次のセルから、表示される文字列か入力（数式）に text を含むセルを探して選ぶ。端まで行ったら先頭へ戻る
  @discardableResult
  func find(_ text: String, backwards: Bool = false) -> Bool {
    guard !text.isEmpty else { return false }
    let addresses = Set(sheet.cells.keys).sorted()
    let matches = addresses.filter { address in
      displayText(at: address).localizedCaseInsensitiveContains(text) || input(at: address).localizedCaseInsensitiveContains(text)
    }
    let next = backwards ? (matches.last { $0 < active } ?? matches.last) : (matches.first { $0 > active } ?? matches.first)
    guard let next else {
      errorMessage = "「\(text)」は見つかりません。"
      return false
    }
    errorMessage = nil
    select(next)
    onReveal()
    return true
  }

  /// 選んだ範囲の集計（Excel の下のバーと同じ）。数が 2 つ以上あるときだけ
  var summary: (sum: Double, average: Double, count: Int, numbers: Int)? {
    guard let range = usedSelection, range.rowCount * range.columnCount > 1 else { return nil }
    var sum = 0.0, numbers = 0, count = 0
    for (address, value) in values where range.contains(address) {
      if value != .empty { count += 1 }
      if case .number(let number) = value {
        sum += number
        numbers += 1
      }
    }
    guard count > 1 else { return nil }
    return (sum, numbers == 0 ? 0 : sum / Double(numbers), count, numbers)
  }

  // MARK: - 行・列・セルの挿入と削除

  /// 行をまるごと選んでいるとき以外は、選んでいる行の数だけ挿入する
  private var selectedRowCount: Int { selection.rowCount > 10_000 ? 1 : selection.rowCount }
  private var selectedColumnCount: Int { selection.columnCount > 1_000 ? 1 : selection.columnCount }

  func insertRows(below: Bool) {
    let at = below ? selection.end.row + 1 : selection.start.row
    commit { $0.insertRows(at: at, count: selectedRowCount, inSheet: sheetIndex) }
  }

  func deleteRows() {
    commit { $0.deleteRows(selection.rows, inSheet: sheetIndex) }
  }

  func insertColumns(right: Bool) {
    let at = right ? selection.end.column + 1 : selection.start.column
    commit { $0.insertColumns(at: at, count: selectedColumnCount, inSheet: sheetIndex) }
  }

  func deleteColumns() {
    commit { $0.deleteColumns(selection.columns, inSheet: sheetIndex) }
  }

  func insertCells(_ shift: Workbook.Shift) {
    commit { $0.insertCells(selection, shift: shift, inSheet: sheetIndex) }
  }

  func deleteCells(_ shift: Workbook.Shift) {
    commit { $0.deleteCells(selection, shift: shift, inSheet: sheetIndex) }
  }
}
