import AppKit
import KinkoCore

/// 表のグリッド全体。左上の角・列見出し・行見出し・セルを並べ、セルの部分だけをスクロールさせる。
/// 見出しはスクロールの位置に合わせて描き直す
final class SheetGridView: NSView {
  let model: SheetEditorModel
  let geometry = SheetGeometry()
  let cells: SheetCellsView
  private let scrollView = NSScrollView()
  private let columnHeader: SheetColumnHeaderView
  private let rowHeader: SheetRowHeaderView
  private let corner: SheetCornerView

  init(model: SheetEditorModel) {
    self.model = model
    cells = SheetCellsView(model: model, geometry: geometry)
    columnHeader = SheetColumnHeaderView(model: model, geometry: geometry)
    rowHeader = SheetRowHeaderView(model: model, geometry: geometry)
    corner = SheetCornerView(model: model)
    super.init(frame: .zero)

    scrollView.documentView = cells
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = true
    scrollView.backgroundColor = .textBackgroundColor
    scrollView.contentView.postsBoundsChangedNotifications = true
    for view in [scrollView, columnHeader, rowHeader, corner] as [NSView] { addSubview(view) }
    // macOS 14 からは既定で枠の外にも描けるので、見出しの番号が下のシートの切り替えに重ならないよう切る
    clipsToBounds = true
    rowHeader.clipsToBounds = true
    columnHeader.clipsToBounds = true
    NotificationCenter.default.addObserver(
      self, selector: #selector(didScroll), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    reload()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override var isFlipped: Bool { true }

  override func layout() {
    super.layout()
    let header = SheetGeometry.headerHeight, side = SheetGeometry.rowHeaderWidth
    corner.frame = NSRect(x: 0, y: 0, width: side, height: header)
    columnHeader.frame = NSRect(x: side, y: 0, width: max(0, bounds.width - side), height: header)
    rowHeader.frame = NSRect(x: 0, y: header, width: side, height: max(0, bounds.height - header))
    scrollView.frame = NSRect(x: side, y: header, width: max(0, bounds.width - side), height: max(0, bounds.height - header))
  }

  /// 表や選択が変わったら描き直す
  func reload() {
    let model = model
    geometry.update(sheet: model.sheet, active: model.active, revision: model.revision) { address in
      let style = model.style(at: address), text = model.displayText(at: address)
      guard style.wraps, !text.isEmpty else { return SheetCellsView.lineHeight(for: style) + 6 }
      return SheetCellsView.wrappedHeight(text, style: style, width: model.sheet.width(ofColumn: address.column))
    }
    if cells.frame.size != geometry.size { cells.setFrameSize(geometry.size) }
    cells.needsDisplay = true
    cells.window?.invalidateCursorRects(for: cells)
    columnHeader.needsDisplay = true
    rowHeader.needsDisplay = true
  }

  @objc private func didScroll() {
    let visible = scrollView.contentView.bounds
    columnHeader.scrollOffset = visible.minX
    rowHeader.scrollOffset = visible.minY
    // 端に近づいたら、行や列を足して先へスクロールできるようにする
    if visible.maxY > geometry.size.height - visible.height {
      geometry.extraRows = geometry.rows + 200
      reload()
    }
    if visible.maxX > geometry.size.width - visible.width {
      geometry.extraColumns = geometry.columns + 10
      reload()
    }
  }
}
