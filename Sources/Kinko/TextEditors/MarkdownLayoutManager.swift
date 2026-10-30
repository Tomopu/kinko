import AppKit

/// コードブロックの背景と引用の線を、文字の後ろだけでなく行の幅いっぱいに描く
final class MarkdownLayoutManager: NSLayoutManager {
  override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
    super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    guard let storage = textStorage, let container = textContainers.first, storage.length > 0 else { return }
    let shown = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
    let whole = NSRange(location: 0, length: storage.length)
    var location = shown.location
    while location < NSMaxRange(shown) {
      var blockRange = NSRange()
      let value = storage.attribute(.kinkoBlock, at: location, longestEffectiveRange: &blockRange, in: whole)
      defer { location = max(NSMaxRange(blockRange), location + 1) }
      guard let block = value as? MarkdownBlock else { continue }

      // 隠した記号（「```」や「> 」）は前の行に属して配置されることがあるので、見えている文字の範囲で測る
      guard let visible = visibleRange(of: blockRange, in: storage) else { continue }
      var rect = NSRect.null
      enumerateLineFragments(forGlyphRange: glyphRange(forCharacterRange: visible, actualCharacterRange: nil)) { lineRect, _, _, _, _ in
        rect = rect.union(lineRect)
      }
      guard !rect.isNull else { continue }
      rect = rect.offsetBy(dx: origin.x, dy: origin.y)
      if block == .code { rect = rect.insetBy(dx: 0, dy: -6) }
      rect.origin.x += container.lineFragmentPadding
      rect.size.width -= container.lineFragmentPadding * 2
      switch block {
      case .code:
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
      case .quote:
        NSColor.tertiaryLabelColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY + 2, width: 3, height: rect.height - 4), xRadius: 1.5, yRadius: 1.5).fill()
      }
    }
  }

  private func visibleRange(of range: NSRange, in storage: NSTextStorage) -> NSRange? {
    func isVisible(_ index: Int) -> Bool {
      let character = storage.mutableString.character(at: index)
      return character != 0x0A && character != 0x0D && storage.attribute(.kinkoHidden, at: index, effectiveRange: nil) == nil
    }
    var start = range.location
    var end = NSMaxRange(range)
    while start < end, !isVisible(start) { start += 1 }
    while end > start, !isVisible(end - 1) { end -= 1 }
    return end > start ? NSRange(location: start, length: end - start) : nil
  }
}
