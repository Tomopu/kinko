import AppKit
import KinkoCore

extension NSAttributedString.Key {
  /// この文字は描かない（記号を隠す）
  static let kinkoHidden = NSAttributedString.Key("KinkoHidden")
  /// この文字を中黒として描く
  static let kinkoBullet = NSAttributedString.Key("KinkoBullet")
  /// この「[ ]」をチェック欄として描く（値はチェック済みかどうか）
  static let kinkoCheckbox = NSAttributedString.Key("KinkoCheckbox")
  /// 行の幅いっぱいに背景や線を描くブロック（値は MarkdownBlock）
  static let kinkoBlock = NSAttributedString.Key("KinkoBlock")
}

@MainActor
enum MarkdownStyle {
  static let bodySize: CGFloat = 14
  static let codeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
  static let codeBackground = NSColor.labelColor.withAlphaComponent(0.07)
  static let checkboxFont = NSFont(name: "Apple Symbols", size: 17) ?? NSFont.systemFont(ofSize: 15)

  static let base: [NSAttributedString.Key: Any] = {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 3
    paragraph.paragraphSpacing = 4
    return [.font: NSFont.systemFont(ofSize: bodySize), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
  }()

  static func apply(_ spans: [MarkdownSpan], to storage: NSTextStorage, activeLine: NSRange, cursor: Int, showsSyntax: Bool) {
    storage.setAttributes(base, range: NSRange(location: 0, length: storage.length))
    for span in spans { style(span, in: storage) }
    for span in spans {
      let isActive = showsSyntax || touches(span.range, activeLine, cursor: cursor)
      for marker in span.markers {
        storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: marker)
        if !isActive {
          storage.addAttribute(.kinkoHidden, value: true, range: marker)
          // 隠した記号は前の行の末尾に置かれることがあり、背景色が残るとその行の端まで帯が出る
          storage.removeAttribute(.backgroundColor, range: marker)
          // 「```」の行は隠すだけだと空の行が残るので、ブロックの上下の余白くらいの高さに縮める
          if span.kind == .codeBlock {
            let line = (storage.string as NSString).lineRange(for: marker)
            storage.addAttribute(.paragraphStyle, value: fenceParagraph, range: line)
          }
        }
      }
      switch span.kind {
      case .bullet where !isActive:
        storage.addAttribute(.kinkoBullet, value: true, range: span.range)
      case .taskBox(let checked):
        if isActive {
          storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: span.range)
        } else {
          storage.addAttributes([.kinkoCheckbox: checked, .font: checkboxFont, .foregroundColor: NSColor.secondaryLabelColor], range: span.range)
        }
      default:
        break
      }
    }
  }

  private static func style(_ span: MarkdownSpan, in storage: NSTextStorage) {
    let range = span.range
    switch span.kind {
    case .heading(let level):
      let sizes: [CGFloat] = [26, 21, 17, 15, 14, 14]
      storage.addAttribute(.font, value: NSFont.systemFont(ofSize: sizes[min(max(level, 1), 6) - 1], weight: .bold), range: range)
      let paragraph = (base[.paragraphStyle] as! NSParagraphStyle).mutableCopy() as! NSMutableParagraphStyle
      paragraph.paragraphSpacingBefore = level <= 2 ? 10 : 6
      storage.addAttribute(.paragraphStyle, value: paragraph, range: range)
    case .strong:
      storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
        guard let font = value as? NSFont else { return }
        storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask), range: subrange)
      }
    case .emphasis:
      // 日本語のフォントには斜体がないので、字を傾けて表す
      storage.addAttribute(.obliqueness, value: 0.18, range: range)
    case .strikethrough, .doneTask:
      storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: NSColor.secondaryLabelColor], range: range)
    case .inlineCode:
      storage.addAttributes([.font: codeFont, .backgroundColor: codeBackground], range: range)
    case .codeBlock:
      let paragraph = indented(10)
      paragraph.tailIndent = -10
      storage.addAttributes([.font: codeFont, .paragraphStyle: paragraph, .kinkoBlock: MarkdownBlock.code], range: range)
    case .blockQuote:
      storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: indented(14), .kinkoBlock: MarkdownBlock.quote], range: range)
    case .link:
      // .link 属性は付けない（付けるとクリックで開けてしまう）。色だけ変える
      storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
    case .bullet:
      storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
    case .taskBox:
      break
    case .thematicBreak:
      storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
    case .table:
      storage.addAttribute(.font, value: codeFont, range: range)
    }
  }

  private static func indented(_ indent: CGFloat) -> NSMutableParagraphStyle {
    let paragraph = (base[.paragraphStyle] as! NSParagraphStyle).mutableCopy() as! NSMutableParagraphStyle
    paragraph.firstLineHeadIndent = indent
    paragraph.headIndent = indent
    return paragraph
  }

  private static let fenceParagraph: NSParagraphStyle = {
    let paragraph = NSMutableParagraphStyle()
    paragraph.minimumLineHeight = 8
    paragraph.maximumLineHeight = 8
    return paragraph
  }()

  /// 装飾がカーソルのある行にかかっているか
  private static func touches(_ range: NSRange, _ line: NSRange, cursor: Int) -> Bool {
    NSIntersectionRange(range, line).length > 0 || (cursor >= range.location && cursor <= NSMaxRange(range))
  }

  nonisolated static func glyph(_ character: UniChar, in font: NSFont) -> CGGlyph? {
    var character = character
    var glyph: CGGlyph = 0
    return CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) ? glyph : nil
  }
}

enum MarkdownBlock: Int {
  case code
  case quote
}
