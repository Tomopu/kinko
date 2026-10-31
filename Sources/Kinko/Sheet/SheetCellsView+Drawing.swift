import AppKit
import KinkoCore

/// セルの描画（目盛り線・塗り・文字・罫線・選択の色・つまみ）
extension SheetCellsView {
  override func draw(_ dirtyRect: NSRect) {
    NSColor.textBackgroundColor.setFill()
    dirtyRect.fill()

    let rows = geometry.row(at: dirtyRect.minY)...geometry.row(at: dirtyRect.maxY)
    let columns = geometry.column(at: dirtyRect.minX)...geometry.column(at: dirtyRect.maxX)
    let selectionRect = geometry.rect(of: model.selection)

    // 目盛りの線（印刷されない薄い線）
    let grid = NSBezierPath()
    for row in rows {
      let y = geometry.y(of: row + 1) - 0.5
      grid.move(to: NSPoint(x: dirtyRect.minX, y: y))
      grid.line(to: NSPoint(x: dirtyRect.maxX, y: y))
    }
    for column in columns {
      let x = geometry.x(of: column + 1) - 0.5
      grid.move(to: NSPoint(x: x, y: dirtyRect.minY))
      grid.line(to: NSPoint(x: x, y: dirtyRect.maxY))
    }
    grid.lineWidth = 1
    Self.gridLineColor.setStroke()
    grid.stroke()

    // 背景色は目盛りの線を隠す（Excel と同じ）
    for row in rows {
      for column in columns {
        let address = CellAddress(row: row, column: column)
        if let fill = model.style(at: address).fillColor {
          fill.nsColor.setFill()
          geometry.rect(of: address).fill()
        }
      }
    }

    // 文字。左揃えの長い文字列は、右隣が空なら隣へはみ出して見せる。
    // はみ出しは左の画面外のセルからも来るので、少し左の列から見る
    let textColumns = max(0, columns.lowerBound - 8)...columns.upperBound
    for row in rows {
      for column in textColumns {
        let address = CellAddress(row: row, column: column)
        let value = model.value(at: address)
        guard value != .empty, address != editingAddress else { continue }
        drawValue(value, at: address, style: model.style(at: address), maxColumn: columns.upperBound + 8)
      }
    }

    // 罫線（自分で引く線）。線の種類と色は辺ごとに違う
    for row in rows {
      for column in columns {
        let address = CellAddress(row: row, column: column)
        let borders = model.style(at: address).borders
        guard !borders.isEmpty else { continue }
        let rect = geometry.rect(of: address)
        let (left, right, top, bottom) = (rect.minX - 0.5, rect.maxX - 0.5, rect.minY - 0.5, rect.maxY - 0.5)
        if let line = borders.top { Self.stroke(line, from: NSPoint(x: left, y: top), to: NSPoint(x: right, y: top)) }
        if let line = borders.bottom { Self.stroke(line, from: NSPoint(x: left, y: bottom), to: NSPoint(x: right, y: bottom)) }
        if let line = borders.left { Self.stroke(line, from: NSPoint(x: left, y: top), to: NSPoint(x: left, y: bottom)) }
        if let line = borders.right { Self.stroke(line, from: NSPoint(x: right, y: top), to: NSPoint(x: right, y: bottom)) }
      }
    }

    // 選んだ範囲は上から薄く色を重ねる（入力先のセルだけは重ねない）
    if model.selection.rowCount > 1 || model.selection.columnCount > 1 {
      NSGraphicsContext.saveGraphicsState()
      let tint = NSBezierPath(rect: selectionRect)
      tint.appendRect(geometry.rect(of: model.active))
      tint.windingRule = .evenOdd
      NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
      tint.fill()
      NSGraphicsContext.restoreGraphicsState()
    }

    // 選択の枠と、右下のつまみ
    NSColor.controlAccentColor.setStroke()
    let border = NSBezierPath(rect: selectionRect.insetBy(dx: 0.5, dy: 0.5).offsetBy(dx: -0.5, dy: -0.5))
    border.lineWidth = 2
    border.stroke()
    if editor == nil {
      let handle = handleRect
      NSColor.textBackgroundColor.setFill()
      handle.insetBy(dx: -1, dy: -1).fill()
      NSColor.controlAccentColor.setFill()
      handle.fill()
    }

    // 数式の入力中にクリックで指した範囲
    if let pointed = pointing?.range {
      let path = NSBezierPath(rect: geometry.rect(of: pointed).insetBy(dx: 1, dy: 1))
      path.setLineDash([4, 3], count: 2, phase: 0)
      path.lineWidth = 1.5
      NSColor.systemOrange.setStroke()
      path.stroke()
    }

    if case .filling = drag, let preview = fillPreview {
      let path = NSBezierPath(rect: geometry.rect(of: preview.range).insetBy(dx: 1, dy: 1))
      path.setLineDash([4, 3], count: 2, phase: 0)
      path.lineWidth = 1.5
      NSColor.secondaryLabelColor.setStroke()
      path.stroke()
    }
  }

  /// 罫線の太さと点線の模様（Excel の見た目に近づける）
  static func pattern(of style: BorderStyle) -> (width: CGFloat, dash: [CGFloat]) {
    switch style {
    case .hair: (1, [1, 1])
    case .thin: (1, [])
    case .dotted: (1, [1, 2])
    case .dashed: (1, [3, 2])
    case .dashDot: (1, [6, 2, 2, 2])
    case .dashDotDot: (1, [6, 2, 2, 2, 2, 2])
    case .slantDashDot: (2, [8, 2, 3, 2])
    case .medium: (2, [])
    case .mediumDashed: (2, [6, 3])
    case .mediumDashDot: (2, [8, 3, 3, 3])
    case .mediumDashDotDot: (2, [8, 3, 3, 3, 3, 3])
    case .thick: (3, [])
    case .double: (1, [])
    }
  }

  /// 1 本の罫線を引く。二重線は、辺をはさんで 2 本の細い線にする
  static func stroke(_ line: BorderLine, from start: NSPoint, to end: NSPoint) {
    (line.color?.nsColor ?? .labelColor).setStroke()
    let (width, dash) = pattern(of: line.style)
    let horizontal = start.y == end.y
    let offsets: [CGFloat] = line.style == .double ? [-1, 1] : [0]
    for offset in offsets {
      let path = NSBezierPath()
      path.move(to: horizontal ? NSPoint(x: start.x, y: start.y + offset) : NSPoint(x: start.x + offset, y: start.y))
      path.line(to: horizontal ? NSPoint(x: end.x, y: end.y + offset) : NSPoint(x: end.x + offset, y: end.y))
      path.lineWidth = width
      if !dash.isEmpty { path.setLineDash(dash, count: dash.count, phase: 0) }
      path.stroke()
    }
  }

  /// Windows の Excel でよく使われる、Mac にないフォントの代わり（表示にだけ使い、書式の名前はそのまま持つ）
  private static let fontSubstitutes = [
    "游ゴシック": "YuGothic", "Yu Gothic": "YuGothic", "游明朝": "YuMincho", "Yu Mincho": "YuMincho",
    "ＭＳ ゴシック": "Hiragino Sans", "ＭＳ Ｐゴシック": "Hiragino Sans", "MS Gothic": "Hiragino Sans", "MS PGothic": "Hiragino Sans",
    "メイリオ": "Hiragino Sans", "Meiryo": "Hiragino Sans",
    "ＭＳ 明朝": "Hiragino Mincho ProN", "ＭＳ Ｐ明朝": "Hiragino Mincho ProN", "MS Mincho": "Hiragino Mincho ProN",
  ]

  /// 書式のフォント。大きさは Excel の 11 ポイントを表の既定の 13 ポイントとして、同じ割合で大きくする。
  /// この Mac にないフォントは既定のフォントで見せる
  static func font(for style: CellStyle) -> NSFont {
    let size = CGFloat(style.fontSize ?? CellStyle.defaultFontSize) * font.pointSize / CGFloat(CellStyle.defaultFontSize)
    var result =
      style.fontName.flatMap { name in
        NSFontManager.shared.font(withFamily: fontSubstitutes[name] ?? name, traits: [], weight: 5, size: size)
      } ?? NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
    if style.bold { result = NSFontManager.shared.convert(result, toHaveTrait: .boldFontMask) }
    return result
  }

  /// 1 行の文字の高さ
  static func lineHeight(for style: CellStyle) -> CGFloat {
    let font = font(for: style)
    return ceil(font.ascender - font.descender)
  }

  /// 書式を反映した文字の属性
  static func attributes(
    for style: CellStyle, value: CellValue, alignment: NSTextAlignment, wraps: Bool = false
  ) -> [NSAttributedString.Key: Any] {
    let font = font(for: style)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    // 日本語は単語の区切りがないので、byWordWrapping でも文字の間で折り返す
    paragraph.lineBreakMode = wraps ? .byWordWrapping : .byClipping
    var color: NSColor
    if case .error = value {
      color = .systemRed
    } else if let textColor = style.textColor {
      color = textColor.nsColor
    } else if let fill = style.fillColor {
      // 背景色だけを付けたセルは、ダークモードでも読めるよう、背景の明るさに合わせて黒か白にする
      color = fill.isLight ? .black : .white
    } else {
      color = .labelColor
    }
    var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    // 日本語のフォントには斜体がないことが多いので、字形を傾けて斜体にする
    if style.italic { attributes[.obliqueness] = 0.18 }
    if style.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
    if style.strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
    return attributes
  }

  static func effectiveAlignment(_ style: CellStyle, value: CellValue) -> NSTextAlignment {
    switch style.alignment {
    case .left: return .left
    case .center: return .center
    case .right: return .right
    case nil:
      switch value {
      case .number: return .right
      case .bool, .error: return .center
      default: return .left
      }
    }
  }

  /// 折り返して表示するのに要る行の高さ（上下の余白を含む）
  static func wrappedHeight(_ text: String, style: CellStyle, width: Double) -> CGFloat {
    let attributes = attributes(for: style, value: .text(text), alignment: .left, wraps: true)
    let bounds = (text as NSString).boundingRect(
      with: NSSize(width: max(1, width - 8), height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, attributes: attributes)
    return ceil(bounds.height) + 6
  }

  private func drawValue(_ value: CellValue, at address: CellAddress, style: CellStyle, maxColumn: Int) {
    let alignment = Self.effectiveAlignment(style, value: value)
    var rect = geometry.rect(of: address)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }

    // 折り返す文字列は、セルの中に複数行で描く
    if case .text = value, style.wraps {
      let attributes = Self.attributes(for: style, value: value, alignment: alignment, wraps: true)
      let text = model.displayText(at: address)
      let inner = rect.insetBy(dx: 4, dy: 3)
      let needed = ceil(
        (text as NSString).boundingRect(
          with: NSSize(width: inner.width, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, attributes: attributes
        ).height)
      let height = min(needed, inner.height)
      let y: CGFloat =
        switch style.verticalAlignment {
        case .top: inner.minY
        case .center: inner.midY - height / 2
        case .bottom, nil: inner.maxY - height
        }
      NSBezierPath(rect: rect).addClip()
      text.draw(
        with: NSRect(x: inner.minX, y: y, width: inner.width, height: height), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
        attributes: attributes)
      return
    }

    let attributes = Self.attributes(for: style, value: value, alignment: alignment)
    // 折り返さないセルの改行は、Excel と同じく 1 行につなげて見せる
    let text = model.displayText(at: address).replacingOccurrences(of: "\n", with: " ")
    let width = (text as NSString).size(withAttributes: attributes).width + 8
    // 数は切れると読み違えるので、Excel と同じく ### にする
    var shown = text
    if case .number = value, width > rect.width { shown = String(repeating: "#", count: max(1, Int(rect.width / 8))) }
    // 左揃えの文字列は、右隣が空（中身も背景色もない）のあいだ、はみ出して見せる
    if case .text = value, alignment == .left, width > rect.width {
      var column = address.column + 1
      while rect.width < width, column <= maxColumn {
        let next = CellAddress(row: address.row, column: column)
        guard model.input(at: next).isEmpty, model.style(at: next).fillColor == nil else { break }
        rect.size.width += geometry.rect(of: next).width
        column += 1
      }
      if rect.width > geometry.rect(of: address).width {
        // はみ出した先の目盛りの線を消す
        NSColor.textBackgroundColor.setFill()
        let base = geometry.rect(of: address)
        NSRect(x: base.maxX - 1, y: rect.minY, width: rect.maxX - base.maxX, height: rect.height - 1).fill()
      }
    }
    let lineHeight = Self.lineHeight(for: style)
    let y: CGFloat =
      switch style.verticalAlignment {
      case .top: rect.minY + 3
      case .center: rect.midY - lineHeight / 2 - 0.5
      case .bottom, nil: rect.maxY - lineHeight - 3
      }
    NSBezierPath(rect: rect).addClip()
    shown.draw(with: NSRect(x: rect.minX + 4, y: y, width: rect.width - 8, height: lineHeight), options: [.usesLineFragmentOrigin], attributes: attributes)
  }

  var handleRect: NSRect {
    let rect = geometry.rect(of: model.selection)
    let size = Self.handleSize
    return NSRect(x: rect.maxX - size / 2 - 1, y: rect.maxY - size / 2 - 1, width: size, height: size)
  }

  override func resetCursorRects() {
    addCursorRect(handleRect.insetBy(dx: -3, dy: -3), cursor: .crosshair)
  }
}
