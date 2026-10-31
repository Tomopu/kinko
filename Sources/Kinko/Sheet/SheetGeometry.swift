import AppKit
import KinkoCore

/// セルの位置と画面上の座標の対応。列ごとに幅が、行ごとに高さが違うので、左端・上端の位置を前もって足し合わせておく
@MainActor
final class SheetGeometry {
  /// 行の既定の高さ
  static let rowHeight: CGFloat = 22
  static let headerHeight: CGFloat = 22
  static let rowHeaderWidth: CGFloat = 52

  /// 表示している行と列の数。中身や選択より少し先まで出し、スクロールで端に近づいたら増やす
  private(set) var rows = 200
  private(set) var columns = 26
  var extraRows = 0
  var extraColumns = 0
  /// 各列の左端の x。最後の要素は表全体の幅
  private(set) var offsets: [CGFloat] = [0]
  /// 各行の上端の y。最後の要素は表全体の高さ
  private(set) var rowOffsets: [CGFloat] = [0]
  /// 折り返す文字や大きな文字に合わせて自動で高くした行。測るのは重いので、表が変わったときだけ測り直す
  private var autoHeights: [Int: CGFloat] = [:]
  private var measuredRevision = -1

  /// measure は、折り返すセルやフォントを変えたセルの中身を表示するのに要る高さ
  func update(sheet: Sheet, active: CellAddress, revision: Int, measure: (CellAddress) -> CGFloat) {
    let used = sheet.usedRange
    rows = min(CellAddress.maxRows, max(200, (used?.end.row ?? 0) + 50, active.row + 30, extraRows))
    columns = min(CellAddress.maxColumns, max(26, (used?.end.column ?? 0) + 10, active.column + 5, extraColumns))
    var offsets: [CGFloat] = [0]
    offsets.reserveCapacity(columns + 1)
    for column in 0..<columns { offsets.append(offsets[column] + sheet.width(ofColumn: column)) }
    self.offsets = offsets

    if revision != measuredRevision {
      measuredRevision = revision
      autoHeights = [:]
      // フォントを変えたセルは、中身がなくても行を高くする（Excel と同じ）
      for (address, style) in sheet.styles where sheet.rowHeights[address.row] == nil
        && ((style.wraps && !sheet[address].isEmpty) || style.fontSize != nil || style.fontName != nil)
      {
        autoHeights[address.row] = max(autoHeights[address.row] ?? 0, measure(address))
      }
    }
    var rowOffsets: [CGFloat] = [0]
    rowOffsets.reserveCapacity(rows + 1)
    for row in 0..<rows {
      let height = sheet.rowHeights[row].map { CGFloat($0) } ?? max(Self.rowHeight, autoHeights[row] ?? 0)
      rowOffsets.append(rowOffsets[row] + height)
    }
    self.rowOffsets = rowOffsets
  }

  var size: NSSize { NSSize(width: offsets[columns], height: rowOffsets[rows]) }

  func x(of column: Int) -> CGFloat { offsets[min(column, columns)] }
  func y(of row: Int) -> CGFloat { rowOffsets[min(max(row, 0), rows)] }
  func height(of row: Int) -> CGFloat { y(of: row + 1) - y(of: row) }

  func column(at x: CGFloat) -> Int { Self.index(in: offsets, count: columns, at: x) }
  func row(at y: CGFloat) -> Int { Self.index(in: rowOffsets, count: rows, at: y) }

  /// 上端（左端）の位置の並びを二分探索して、position を含む行（列）を探す
  private static func index(in starts: [CGFloat], count: Int, at position: CGFloat) -> Int {
    var low = 0, high = count - 1
    while low < high {
      let mid = (low + high + 1) / 2
      if starts[mid] <= position { low = mid } else { high = mid - 1 }
    }
    return max(0, low)
  }

  func cell(at point: NSPoint) -> CellAddress { CellAddress(row: row(at: point.y), column: column(at: point.x)) }

  func rect(of cell: CellAddress) -> NSRect {
    rect(of: CellRange(cell))
  }

  /// 範囲の四角。表示している行・列の外へはみ出す部分（行・列をまるごと選んだとき）は切り詰める
  func rect(of range: CellRange) -> NSRect {
    let left = x(of: range.start.column), right = x(of: min(range.end.column, columns - 1) + 1)
    let top = y(of: range.start.row), bottom = y(of: min(range.end.row, rows - 1) + 1)
    return NSRect(x: left, y: top, width: max(0, right - left), height: max(0, bottom - top))
  }
}
