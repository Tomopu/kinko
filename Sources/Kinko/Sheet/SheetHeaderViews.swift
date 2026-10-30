import AppKit
import KinkoCore

/// 列見出し（A, B, C…）。クリックで列を選び、境目のドラッグで幅を変える
final class SheetColumnHeaderView: NSView {
  private let model: SheetEditorModel
  private let geometry: SheetGeometry
  var scrollOffset: CGFloat = 0 { didSet { needsDisplay = true } }

  private enum Drag {
    case selecting(anchor: Int)
    case resizing(column: Int, startX: CGFloat, startWidth: CGFloat)
  }
  private var drag: Drag?

  init(model: SheetEditorModel, geometry: SheetGeometry) {
    self.model = model
    self.geometry = geometry
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override var isFlipped: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.windowBackgroundColor.setFill()
    bounds.fill()
    let first = geometry.column(at: scrollOffset)
    let last = geometry.column(at: scrollOffset + bounds.width)
    let selected = model.selection.columns
    for column in first...last {
      let rect = NSRect(x: geometry.x(of: column) - scrollOffset, y: 0, width: geometry.x(of: column + 1) - geometry.x(of: column), height: bounds.height)
      let isSelected = selected.contains(column)
      if isSelected {
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        rect.fill()
      }
      SheetMenus.drawHeaderLabel(CellAddress.columnName(column), in: rect, bold: isSelected)
      NSColor.separatorColor.setFill()
      NSRect(x: rect.maxX - 1, y: 0, width: 1, height: bounds.height).fill()
    }
    NSColor.separatorColor.setFill()
    NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
  }

  /// x に一番近い列の右の境目（±4pt 以内）
  private func border(near x: CGFloat) -> Int? {
    let column = geometry.column(at: x + scrollOffset)
    for candidate in [column - 1, column] where candidate >= 0 {
      if abs(geometry.x(of: candidate + 1) - scrollOffset - x) <= 4 { return candidate }
    }
    return nil
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .cursorUpdate], owner: self))
  }

  override func mouseMoved(with event: NSEvent) {
    let x = convert(event.locationInWindow, from: nil).x
    (border(near: x) != nil ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(cellsView)
    let x = convert(event.locationInWindow, from: nil).x
    if let column = border(near: x) {
      // 境目のダブルクリックで、中身に合わせた幅にする
      if event.clickCount == 2 {
        model.autoFit(column: column) { text, style in
          let attributes = SheetCellsView.attributes(for: style, value: .text(text), alignment: .left)
          return (text as NSString).size(withAttributes: attributes).width
        }
        return
      }
      drag = .resizing(column: column, startX: x, startWidth: model.sheet.width(ofColumn: column))
      return
    }
    let column = geometry.column(at: x + scrollOffset)
    let anchor = event.modifierFlags.contains(.shift) ? model.active.column : column
    selectColumns(anchor, column)
    drag = .selecting(anchor: anchor)
  }

  override func mouseDragged(with event: NSEvent) {
    let x = convert(event.locationInWindow, from: nil).x
    switch drag {
    case .resizing(let column, let startX, let startWidth):
      model.setWidth(startWidth + x - startX, ofColumn: column)
    case .selecting(let anchor):
      selectColumns(anchor, geometry.column(at: x + scrollOffset))
    case nil:
      break
    }
  }

  override func mouseUp(with event: NSEvent) { drag = nil }

  private func selectColumns(_ a: Int, _ b: Int) {
    model.select(
      range: CellRange(CellAddress(row: 0, column: a), CellAddress(row: CellAddress.maxRows - 1, column: b)),
      active: CellAddress(row: 0, column: a))
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    let column = geometry.column(at: convert(event.locationInWindow, from: nil).x + scrollOffset)
    // 列をまるごと選んでいる中で右クリックしたなら、その選択のまま。そうでなければその列を選ぶ
    let isWholeColumns = model.selection.rowCount == CellAddress.maxRows
    if !isWholeColumns || !model.selection.columns.contains(column) { selectColumns(column, column) }
    return SheetMenus.columnMenu(target: cellsView)
  }

  private var cellsView: SheetCellsView? { (superview as? SheetGridView)?.cells }
}

/// 行見出し（1, 2, 3…）。クリックで行を選ぶ
final class SheetRowHeaderView: NSView {
  private let model: SheetEditorModel
  private let geometry: SheetGeometry
  var scrollOffset: CGFloat = 0 { didSet { needsDisplay = true } }

  private enum Drag {
    case selecting(anchor: Int)
    case resizing(row: Int, startY: CGFloat, startHeight: CGFloat)
  }
  private var drag: Drag?

  init(model: SheetEditorModel, geometry: SheetGeometry) {
    self.model = model
    self.geometry = geometry
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override var isFlipped: Bool { true }

  /// y に一番近い行の下の境目（±4pt 以内）
  private func border(near y: CGFloat) -> Int? {
    let row = geometry.row(at: y + scrollOffset)
    for candidate in [row - 1, row] where candidate >= 0 {
      if abs(geometry.y(of: candidate + 1) - scrollOffset - y) <= 4 { return candidate }
    }
    return nil
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .cursorUpdate], owner: self))
  }

  override func mouseMoved(with event: NSEvent) {
    let y = convert(event.locationInWindow, from: nil).y
    (border(near: y) != nil ? NSCursor.resizeUpDown : NSCursor.arrow).set()
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.windowBackgroundColor.setFill()
    bounds.fill()
    let first = geometry.row(at: scrollOffset)
    let last = geometry.row(at: scrollOffset + bounds.height)
    let selected = model.selection.rows
    for row in first...last {
      let rect = NSRect(x: 0, y: geometry.y(of: row) - scrollOffset, width: bounds.width, height: geometry.height(of: row))
      let isSelected = selected.contains(row)
      if isSelected {
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        rect.fill()
      }
      SheetMenus.drawHeaderLabel(String(row + 1), in: rect, bold: isSelected)
      NSColor.separatorColor.setFill()
      NSRect(x: 0, y: rect.maxY - 1, width: bounds.width, height: 1).fill()
    }
    NSColor.separatorColor.setFill()
    NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder((superview as? SheetGridView)?.cells)
    let y = convert(event.locationInWindow, from: nil).y
    if let row = border(near: y) {
      // 境目のダブルクリックで、自動の高さ（折り返す文字に合わせる）に戻す
      if event.clickCount == 2 {
        model.setHeight(nil, ofRow: row)
        return
      }
      drag = .resizing(row: row, startY: y, startHeight: geometry.height(of: row))
      return
    }
    let row = geometry.row(at: y + scrollOffset)
    let anchor = event.modifierFlags.contains(.shift) ? model.active.row : row
    drag = .selecting(anchor: anchor)
    selectRows(anchor, row)
  }

  override func mouseDragged(with event: NSEvent) {
    let y = convert(event.locationInWindow, from: nil).y
    switch drag {
    case .resizing(let row, let startY, let startHeight):
      model.setHeight(startHeight + y - startY, ofRow: row)
    case .selecting(let anchor):
      selectRows(anchor, geometry.row(at: y + scrollOffset))
    case nil:
      break
    }
  }

  override func mouseUp(with event: NSEvent) { drag = nil }

  private func selectRows(_ a: Int, _ b: Int) {
    model.select(
      range: CellRange(CellAddress(row: a, column: 0), CellAddress(row: b, column: CellAddress.maxColumns - 1)),
      active: CellAddress(row: a, column: 0))
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    let row = geometry.row(at: convert(event.locationInWindow, from: nil).y + scrollOffset)
    let isWholeRows = model.selection.columnCount == CellAddress.maxColumns
    if !isWholeRows || !model.selection.rows.contains(row) { selectRows(row, row) }
    return SheetMenus.rowMenu(target: (superview as? SheetGridView)?.cells)
  }
}

/// 左上の角。クリックですべて選ぶ
final class SheetCornerView: NSView {
  private let model: SheetEditorModel

  init(model: SheetEditorModel) {
    self.model = model
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.windowBackgroundColor.setFill()
    bounds.fill()
    NSColor.separatorColor.setFill()
    NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()
    NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
  }

  override func mouseDown(with event: NSEvent) {
    let cells = (superview as? SheetGridView)?.cells
    window?.makeFirstResponder(cells)
    cells?.selectAll(nil)
  }
}
