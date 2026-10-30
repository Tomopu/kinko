import AppKit
import KinkoCore

extension SheetEditorModel {
  /// 他のアプリへは表示どおりの値をタブ区切りで、Kinko の中へは数式のまま渡す。
  /// どちらもクリップボードには平文で残る（ほかのアプリからも読める）ことに注意
  func copy() {
    guard let range = usedSelection else { return }
    var rows: [[String]] = []
    var inputs: [[String]] = []
    var styles: [[CellStyle]] = []
    for row in range.rows {
      rows.append(range.columns.map { displayText(at: CellAddress(row: row, column: $0)) })
      inputs.append(range.columns.map { input(at: CellAddress(row: row, column: $0)) })
      styles.append(range.columns.map { style(at: CellAddress(row: row, column: $0)) })
    }
    let clip = CellClip(row: range.start.row, column: range.start.column, inputs: inputs, styles: styles)
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(rows.map { $0.joined(separator: "\t") }.joined(separator: "\n"), forType: .string)
    if let data = try? JSONEncoder().encode(clip) { pasteboard.setData(data, forType: CellClip.type) }
  }

  func cut() {
    copy()
    clearSelection()
  }

  func paste() {
    let pasteboard = NSPasteboard.general
    let origin = active
    if let data = pasteboard.data(forType: CellClip.type), let clip = try? JSONDecoder().decode(CellClip.self, from: data) {
      // 数式は、貼り付けた位置へずらす（=A1 を 1 行下へ貼ると =A2）
      let rowOffset = origin.row - clip.row
      let columnOffset = origin.column - clip.column
      commit { workbook in
        for (r, row) in clip.inputs.enumerated() {
          for (c, input) in row.enumerated() {
            let target = CellAddress(row: origin.row + r, column: origin.column + c)
            guard target.isValid else { continue }
            workbook.sheets[sheetIndex][target] =
              CellInput.isFormula(input) ? Formula.shifted(input, rowOffset: rowOffset, columnOffset: columnOffset) : input
            // 書式も貼り付ける（Excel の通常の貼り付けと同じ）
            if let styles = clip.styles, r < styles.count, c < styles[r].count {
              workbook.sheets[sheetIndex][style: target] = styles[r][c]
            }
          }
        }
      }
      selectPasted(rows: clip.inputs.count, columns: clip.inputs.map(\.count).max() ?? 1)
    } else if let text = pasteboard.string(forType: .string) {
      let rows = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        .reversed().drop(while: { $0 == [""] }).reversed()
      commit { workbook in
        for (r, row) in rows.enumerated() {
          for (c, input) in row.enumerated() {
            let target = CellAddress(row: origin.row + r, column: origin.column + c)
            if target.isValid { workbook.sheets[sheetIndex][target] = input }
          }
        }
      }
      selectPasted(rows: rows.count, columns: rows.map(\.count).max() ?? 1)
    }
  }

  private func selectPasted(rows: Int, columns: Int) {
    let end = CellAddress(row: active.row + max(rows, 1) - 1, column: active.column + max(columns, 1) - 1)
    select(range: CellRange(active, clamped(end)), active: active)
  }
}

/// Kinko の中でのコピー＆ペースト用。数式を数式のまま運ぶ
struct CellClip: Codable {
  static let type = NSPasteboard.PasteboardType("com.tomopu.kinko.cells")

  /// コピー元の左上
  var row: Int
  var column: Int
  var inputs: [[String]]
  var styles: [[CellStyle]]?
}
