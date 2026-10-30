import AppKit
import KinkoCore
import Observation

/// 表の編集画面の状態。表の中身・選んでいる範囲・計算結果・取り消しの履歴を持つ
@MainActor @Observable
final class SheetEditorModel {
  private(set) var workbook: Workbook
  private(set) var sheetIndex = 0
  /// 選んでいる範囲
  private(set) var selection = CellRange(CellAddress(row: 0, column: 0))
  /// 入力先のセル（範囲の中で白く残る 1 つ）
  private(set) var active = CellAddress(row: 0, column: 0)
  /// 数式バーに出す文字列。セルを選ぶと、そのセルの入力に戻る
  var formulaText = ""
  /// 今のシートの計算結果（中身のあるセルだけ）
  private(set) var values: [CellAddress: CellValue] = [:]
  var errorMessage: String?
  /// 次に引く罫線の種類と色（罫線の画面で選ぶ。Excel の「線のスタイル」「線の色」と同じく、引くまで覚えておく）
  var borderLine = BorderLine()

  /// 表を変えたら呼ぶ（金庫の中身に書き戻す）
  @ObservationIgnored var onChange: (Workbook) -> Void = { _ in }
  /// 表示を描き直してほしいときに呼ぶ（グリッドは SwiftUI ではないので、自分で知らせる）
  @ObservationIgnored var onDisplayChange: () -> Void = {}
  /// 入力先のセルが見えるところまでスクロールしてほしいとき（検索で見つけたとき）
  @ObservationIgnored var onReveal: () -> Void = {}
  /// 表の中身・シート・列の幅・行の高さが変わるたびに増える。グリッドは、これが変わったときだけ行の高さを測り直す
  @ObservationIgnored private(set) var revision = 0

  private var undoStack: [Snapshot] = []
  private var redoStack: [Snapshot] = []
  private static let undoLimit = 100

  private struct Snapshot {
    var workbook: Workbook
    var sheetIndex: Int
    var selection: CellRange
    var active: CellAddress
  }

  init(workbook: Workbook) {
    self.workbook = workbook
    recalculate()
    formulaText = input(at: active)
  }

  var sheet: Sheet { workbook.sheets[sheetIndex] }
  var canUndo: Bool { !undoStack.isEmpty }
  var canRedo: Bool { !redoStack.isEmpty }

  func input(at address: CellAddress) -> String { sheet[address] }
  func value(at address: CellAddress) -> CellValue { values[address] ?? .empty }
  func style(at address: CellAddress) -> CellStyle { sheet[style: address] }
  /// 書式バーに出す、入力先のセルの書式
  var activeStyle: CellStyle { style(at: active) }

  /// セルに表示する文字列。表示形式があればそれで、数式でない数は入力したとおりに（「10%」が 0.1 にならないように）
  func displayText(at address: CellAddress) -> String {
    let value = value(at: address)
    guard case .number(let number) = value else { return value.displayText }
    if let formatted = style(at: address).numberFormat.format(number) { return formatted }
    let input = input(at: address)
    return CellInput.isFormula(input) ? value.displayText : input.trimmingCharacters(in: .whitespaces)
  }

  /// 外（金庫）で中身が変わったときに受け取る。自分が書き戻した値なら何もしない
  func update(from workbook: Workbook) {
    guard workbook != self.workbook else { return }
    self.workbook = workbook
    sheetIndex = min(sheetIndex, workbook.sheets.count - 1)
    recalculate()
    onDisplayChange()
  }

  // MARK: - 選択

  func select(_ cell: CellAddress, extending: Bool = false) {
    let cell = clamped(cell)
    if extending {
      selection = CellRange(active, cell)
    } else {
      active = cell
      selection = CellRange(cell)
    }
    selectionChanged()
  }

  /// 行や列をまるごと選ぶときなど、範囲と入力先を直接決める
  func select(range: CellRange, active: CellAddress) {
    self.active = clamped(active)
    selection = range
    selectionChanged()
  }

  /// 矢印キーなどで入力先を動かす。extending なら範囲を広げる（入力先は動かさず、反対の角を動かす）
  func move(rows: Int, columns: Int, extending: Bool) {
    if extending {
      // 入力先と反対側の角を動かす
      let corner = CellAddress(
        row: selection.start.row == active.row ? selection.end.row : selection.start.row,
        column: selection.start.column == active.column ? selection.end.column : selection.start.column)
      selection = CellRange(active, clamped(CellAddress(row: corner.row + rows, column: corner.column + columns)))
      selectionChanged()
    } else {
      select(CellAddress(row: active.row + rows, column: active.column + columns))
    }
  }

  /// 範囲を選んでいるとき、Return や Tab は範囲の中を順に回る（Excel と同じ）
  func advance(rows: Int, columns: Int) {
    guard selection.rowCount > 1 || selection.columnCount > 1 else {
      move(rows: rows, columns: columns, extending: false)
      return
    }
    var row = active.row, column = active.column
    if rows != 0 {
      row += rows
      if row > selection.end.row { row = selection.start.row; column += 1 }
      if row < selection.start.row { row = selection.end.row; column -= 1 }
      if column > selection.end.column { column = selection.start.column }
      if column < selection.start.column { column = selection.end.column }
    } else {
      column += columns
      if column > selection.end.column { column = selection.start.column; row += 1 }
      if column < selection.start.column { column = selection.end.column; row -= 1 }
      if row > selection.end.row { row = selection.start.row }
      if row < selection.start.row { row = selection.end.row }
    }
    active = CellAddress(row: row, column: column)
    selectionChanged()
  }

  func clamped(_ cell: CellAddress) -> CellAddress {
    CellAddress(
      row: min(max(cell.row, 0), CellAddress.maxRows - 1), column: min(max(cell.column, 0), CellAddress.maxColumns - 1))
  }

  private func selectionChanged() {
    formulaText = input(at: active)
    onDisplayChange()
  }

  /// 中身のあるところだけに縮めた選択範囲（行・列まるごと選んでいるときに、100 万行を相手にしないため）
  var usedSelection: CellRange? {
    guard let used = sheet.usedRange else { return nil }
    let top = max(selection.start.row, 0), left = max(selection.start.column, 0)
    let bottom = min(selection.end.row, used.end.row), right = min(selection.end.column, used.end.column)
    guard top <= bottom, left <= right else { return nil }
    return CellRange(CellAddress(row: top, column: left), CellAddress(row: bottom, column: right))
  }

  // MARK: - 入力

  func setInput(_ input: String, at address: CellAddress) {
    guard sheet[address] != input else { return }
    commit { $0.sheets[sheetIndex][address] = input }
  }

  /// セルの中で改行して入力したときは、折り返しもオンにする（Excel と同じ。1 回の取り消しで両方戻る）
  func setInput(_ input: String, at address: CellAddress, wrapping: Bool) {
    guard wrapping, !style(at: address).wraps else { return setInput(input, at: address) }
    commit { workbook in
      workbook.sheets[sheetIndex][address] = input
      workbook.sheets[sheetIndex][style: address].wraps = true
    }
  }

  /// 数式バーで Return を押した
  func commitFormulaBar() {
    setInput(formulaText, at: active)
    formulaText = input(at: active)
  }

  func clearSelection() {
    guard let range = usedSelection else { return }
    commit { workbook in
      for address in workbook.sheets[sheetIndex].cells.keys where range.contains(address) {
        workbook.sheets[sheetIndex][address] = ""
      }
    }
  }

  /// 選んでいる範囲を、つまみで引っぱった先まで埋める
  func fill(_ direction: FillDirection, count: Int, incrementsSingleNumbers: Bool) {
    // 行・列をまるごと選んでの複製は、何百万セルにもなるので受け付けない
    let source = selection
    guard count > 0, source.rowCount * source.columnCount <= 100_000 else { return }
    commit { workbook in
      workbook.sheets[sheetIndex].fill(
        from: source, direction: direction, count: count, incrementsSingleNumbers: incrementsSingleNumbers)
    }
    let end: CellAddress
    switch direction {
    case .down: end = CellAddress(row: source.end.row + count, column: source.end.column)
    case .up: end = CellAddress(row: source.start.row - count, column: source.start.column)
    case .right: end = CellAddress(row: source.end.row, column: source.end.column + count)
    case .left: end = CellAddress(row: source.start.row, column: source.start.column - count)
    }
    let corner = direction == .down || direction == .right ? source.start : source.end
    selection = CellRange(corner, clamped(end))
    selectionChanged()
  }

  // MARK: - 列の幅と行の高さ

  /// 列の中で一番長い表示に幅を合わせる。measure は文字列の幅を測る（フォントは画面側が知っている）
  func autoFit(column: Int, measure: (String, CellStyle) -> Double) {
    var widest = 0.0
    for address in sheet.cells.keys where address.column == column {
      widest = max(widest, measure(displayText(at: address), style(at: address)))
    }
    guard widest > 0 else { return }
    setWidth(widest + 14, ofColumn: column)
  }

  func setWidth(_ width: Double, ofColumn column: Int) {
    let width = min(max(width, 24), 800).rounded()
    guard sheet.width(ofColumn: column) != width else { return }
    // 幅を変えるたびに履歴を積むと、ドラッグ 1 回で何十回も取り消すことになるので、ここでは積まない
    workbook.sheets[sheetIndex].columnWidths[column] = width == Sheet.defaultColumnWidth ? nil : width
    revision += 1
    onChange(workbook)
    onDisplayChange()
  }

  /// 行の高さを手で決める。nil なら自動（折り返す文字に合わせる）に戻す
  func setHeight(_ height: Double?, ofRow row: Int) {
    let height = height.map { min(max($0, 12), 409).rounded() }
    guard sheet.rowHeights[row] != height else { return }
    workbook.sheets[sheetIndex].rowHeights[row] = height
    revision += 1
    onChange(workbook)
    onDisplayChange()
  }

  // MARK: - シート

  func selectSheet(_ index: Int) {
    guard workbook.sheets.indices.contains(index), index != sheetIndex else { return }
    sheetIndex = index
    recalculate()
    select(CellAddress(row: 0, column: 0))
  }

  func addSheet() {
    commit { workbook in
      let index = workbook.addSheet()
      sheetIndex = index
    }
    select(CellAddress(row: 0, column: 0))
  }

  func renameSheet(_ index: Int, to name: String) {
    commit { try $0.renameSheet(index, to: name) }
  }

  func removeSheet(_ index: Int) {
    commit { workbook in
      workbook.removeSheet(index)
      sheetIndex = min(sheetIndex, workbook.sheets.count - 1)
    }
  }

  // MARK: - 取り消し

  func undo() {
    guard let previous = undoStack.popLast() else { return }
    redoStack.append(snapshot)
    restore(previous)
  }

  func redo() {
    guard let next = redoStack.popLast() else { return }
    undoStack.append(snapshot)
    restore(next)
  }

  private var snapshot: Snapshot {
    Snapshot(workbook: workbook, sheetIndex: sheetIndex, selection: selection, active: active)
  }

  private func restore(_ snapshot: Snapshot) {
    workbook = snapshot.workbook
    sheetIndex = min(snapshot.sheetIndex, workbook.sheets.count - 1)
    selection = snapshot.selection
    active = snapshot.active
    recalculate()
    onChange(workbook)
    selectionChanged()
  }

  // MARK: - 内部

  /// 表を変える。変わったら履歴に積み、計算し直して、金庫へ書き戻す
  func commit(_ change: (inout Workbook) throws -> Void) {
    let before = snapshot
    var changed = workbook
    do {
      try change(&changed)
    } catch {
      errorMessage = error.localizedDescription
      return
    }
    errorMessage = nil
    guard changed != workbook else {
      onDisplayChange()
      return
    }
    undoStack.append(before)
    if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
    redoStack.removeAll()
    workbook = changed
    sheetIndex = min(sheetIndex, workbook.sheets.count - 1)
    recalculate()
    onChange(workbook)
    selectionChanged()
  }

  private func recalculate() {
    revision += 1
    values = Calculator(workbook: workbook).values(sheet: sheetIndex)
  }
}
