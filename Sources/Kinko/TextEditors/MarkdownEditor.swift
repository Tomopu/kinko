import AppKit
import KinkoCore
import SwiftUI

/// Obsidian のライブプレビューのような Markdown エディタ。
/// 本文は Markdown の文字列のまま持ち、見た目だけを変える。見出しや太字はその場で整形し、
/// 「##」「**」のような記号は、カーソルのある行でだけ薄く見せて、それ以外の行では隠す。
/// Web の部品（WKWebView と JavaScript）を使わないので、依存ライブラリと攻撃面が増えない。リンクも開かない
struct MarkdownEditor: NSViewRepresentable {
  @Binding var text: String
  /// true なら記号を隠さない
  var showsSyntax: Bool

  func makeNSView(context: Context) -> NSScrollView {
    // 記号を隠すには文字の形（glyph）を差し替える必要があり、それができる TextKit 1 を明示的に組み立てる
    let storage = NSTextStorage()
    let layoutManager = MarkdownLayoutManager()
    layoutManager.delegate = context.coordinator
    storage.addLayoutManager(layoutManager)
    let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
    container.widthTracksTextView = true
    layoutManager.addTextContainer(container)

    let textView = MarkdownTextView(frame: .zero, textContainer: container)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.configureForSecrets()
    textView.delegate = context.coordinator
    textView.typingAttributes = MarkdownStyle.base
    textView.string = text

    let scrollView = NSScrollView()
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.documentView = textView

    context.coordinator.textView = textView
    context.coordinator.showsSyntax = showsSyntax
    context.coordinator.restyle()
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    let coordinator = context.coordinator
    coordinator.text = $text
    guard let textView = coordinator.textView else { return }
    var needsRestyle = false
    if textView.string != text {
      textView.string = text
      needsRestyle = true
    }
    if coordinator.showsSyntax != showsSyntax {
      coordinator.showsSyntax = showsSyntax
      needsRestyle = true
    }
    if needsRestyle { coordinator.restyle() }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text)
  }

  @MainActor
  final class Coordinator: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate {
    var text: Binding<String>
    weak var textView: NSTextView?
    var showsSyntax = false
    private var activeLine: NSRange?
    private var isRestylePending = false

    init(text: Binding<String>) {
      self.text = text
    }

    func textDidChange(_ notification: Notification) {
      guard let textView else { return }
      text.wrappedValue = textView.string
      activeLine = nil
      scheduleRestyle()
    }

    /// リストの行で Return を押したら、次の行にも同じ記号を付ける。中身のない項目なら記号を消してリストを終える
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
      guard selector == #selector(NSResponder.insertNewline(_:)), !textView.hasMarkedText() else { return false }
      let selection = textView.selectedRange()
      guard selection.length == 0 else { return false }
      let string = textView.string as NSString
      let lineStart = string.lineRange(for: selection).location
      let prefix = string.substring(with: NSRange(location: lineStart, length: selection.location - lineStart))
      switch MarkdownLists.continuation(for: prefix) {
      case .continueWith(let marker):
        textView.insertText("\n" + marker, replacementRange: selection)
        return true
      case .endList(let length):
        // カーソルの後ろに文字が残っているときは、普通に改行する
        var lineEnd = 0
        string.getLineStart(nil, end: nil, contentsEnd: &lineEnd, for: selection)
        guard lineEnd == selection.location else { return false }
        textView.insertText("", replacementRange: NSRange(location: lineStart, length: length))
        return true
      case .none:
        return false
      }
    }

    /// 行頭で「[ ]」や「[]」のあとに空白を打ったら「- [ ] 」にする
    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
      guard let replacementString, range.length == 0, !textView.hasMarkedText() else { return true }
      let string = textView.string as NSString
      let lineStart = string.lineRange(for: range).location
      let prefixRange = NSRange(location: lineStart, length: range.location - lineStart)
      guard let replacement = MarkdownLists.checkboxShortcut(linePrefix: string.substring(with: prefixRange), typed: replacementString) else {
        return true
      }
      // 変更の確認の途中で別の変更を入れると AppKit が混乱するので、空白の入力は止めて、あとで置き換える
      DispatchQueue.main.async {
        textView.insertText(replacement, replacementRange: prefixRange)
      }
      return false
    }

    func textViewDidChangeSelection(_ notification: Notification) {
      guard let textView else { return }
      // カーソルが別の行へ移ったときだけ、記号の見せ方を変える
      let string = textView.string as NSString
      let line = string.lineRange(for: textView.selectedRange())
      if line != activeLine { scheduleRestyle() }
    }

    /// 入力の処理中に文字の属性を書き換えると AppKit が嫌うので、一息おいてまとめて整形する
    private func scheduleRestyle() {
      guard !isRestylePending else { return }
      isRestylePending = true
      DispatchQueue.main.async { [weak self] in
        self?.isRestylePending = false
        self?.restyle()
      }
    }

    func restyle() {
      // 日本語の変換中に属性を変えると、変換中の文字が崩れるので触らない（確定したら textDidChange で整形される）
      guard let textView, let storage = textView.textStorage, !textView.hasMarkedText() else { return }
      let string = storage.string as NSString
      let selection = textView.selectedRange()
      let line = string.lineRange(for: selection)
      activeLine = line

      storage.beginEditing()
      MarkdownStyle.apply(MarkdownSpans.parse(storage.string), to: storage, activeLine: line, cursor: selection.location, showsSyntax: showsSyntax)
      storage.endEditing()
      textView.typingAttributes = MarkdownStyle.base
    }

    /// 隠す印の付いた文字は形を描かず（.null）、箇条書きの「-」は中黒（•）の形に差し替える
    nonisolated func layoutManager(
      _ layoutManager: NSLayoutManager,
      shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
      properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
      characterIndexes: UnsafePointer<Int>,
      font: NSFont,
      forGlyphRange glyphRange: NSRange
    ) -> Int {
      guard let storage = layoutManager.textStorage else { return 0 }
      let count = glyphRange.length
      var newGlyphs: [CGGlyph] = []
      var newProperties: [NSLayoutManager.GlyphProperty] = []
      for index in 0..<count {
        let character = characterIndexes[index]
        guard character < storage.length else { continue }
        let attributes = storage.attributes(at: character, effectiveRange: nil)
        var hides = attributes[.kinkoHidden] != nil
        var replacement = attributes[.kinkoBullet] != nil ? MarkdownStyle.glyph(0x2022, in: font) : nil
        // 「[x]」の「[」を ☑ に、残りの 2 文字を描かない
        if let checked = attributes[.kinkoCheckbox] as? Bool {
          if storage.mutableString.character(at: character) == 0x5B {
            replacement = MarkdownStyle.glyph(checked ? 0x2611 : 0x2610, in: font)
          } else {
            hides = true
          }
        }
        let bullet = replacement
        guard hides || bullet != nil else { continue }
        if newGlyphs.isEmpty {
          newGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: count))
          newProperties = Array(UnsafeBufferPointer(start: properties, count: count))
        }
        if hides {
          newProperties[index] = .null
        } else if let bullet {
          newGlyphs[index] = bullet
        }
      }
      guard !newGlyphs.isEmpty else { return 0 }
      layoutManager.setGlyphs(newGlyphs, properties: newProperties, characterIndexes: characterIndexes, font: font, forGlyphRange: glyphRange)
      return count
    }
  }
}

/// チェック欄（☐ ☑）をクリックすると、[ ] と [x] を切り替える
final class MarkdownTextView: NSTextView {
  override func mouseDown(with event: NSEvent) {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if modifiers.isEmpty, event.clickCount == 1, toggleCheckbox(at: convert(event.locationInWindow, from: nil)) {
      return
    }
    super.mouseDown(with: event)
  }

  private func toggleCheckbox(at point: NSPoint) -> Bool {
    guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return false }
    let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
    let glyph = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
    guard glyph < layoutManager.numberOfGlyphs else { return false }
    // 行の右側の何もない所をクリックしたときに反応しないよう、☐ の形の上かを確かめる
    let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
    guard rect.insetBy(dx: -3, dy: -3).contains(containerPoint) else { return false }
    let index = layoutManager.characterIndexForGlyph(at: glyph)
    let line = (storage.string as NSString).lineRange(for: NSRange(location: index, length: 0))
    var box = NSRange()
    guard storage.attribute(.kinkoCheckbox, at: index, longestEffectiveRange: &box, in: line) != nil, box.length == 3 else {
      return false
    }
    let mark = NSRange(location: box.location + 1, length: 1)
    let isChecked = storage.mutableString.character(at: mark.location) != 0x20
    // 切り替えでカーソルがその行へ移ると記号が見えてしまうので、カーソルは元の位置に戻す
    let selection = selectedRanges
    window?.makeFirstResponder(self)
    insertText(isChecked ? " " : "x", replacementRange: mark)
    selectedRanges = selection
    return true
  }
}
