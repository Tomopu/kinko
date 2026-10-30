import AppKit
import KinkoCore

/// セルの中の入力欄（入力・確定・数式の参照をクリックで入れる）
extension SheetCellsView: NSTextFieldDelegate {
  /// セルの上に入力欄を重ねて編集を始める。replacing なら空から（打ち始め）、そうでなければ今の入力を直す
  func beginEditing(replacing: Bool) {
    finishEditing(commit: true)
    scrollToActive()
    let address = model.active
    let field = NSTextField(frame: editorFrame(for: address, text: replacing ? "" : model.input(at: address)))
    field.stringValue = replacing ? "" : model.input(at: address)
    field.font = Self.font
    field.isBordered = false
    field.isBezeled = false
    field.focusRingType = .none
    field.drawsBackground = true
    field.backgroundColor = .textBackgroundColor
    // 折り返すセルは入力欄の中でも折り返す。折り返さないセルは横へ伸ばし、改行したぶんだけ縦に伸ばす
    let wraps = model.style(at: address).wraps
    field.usesSingleLineMode = false
    field.cell?.isScrollable = !wraps
    field.cell?.wraps = wraps
    field.lineBreakMode = wraps ? .byWordWrapping : .byClipping
    field.delegate = self
    insertedLineBreak = false
    addSubview(field)
    editor = field
    editingAddress = address
    isTypingNewValue = replacing
    window?.makeFirstResponder(field)
    // 入力欄を選ぶと全体が選択されるので、カーソルを末尾に置く
    if let text = field.currentEditor() {
      text.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0)
    }
    model.formulaText = field.stringValue
    needsDisplay = true
  }

  /// 入力欄の大きさ。中身が長ければ右へ広げる（Excel と同じ）
  private func editorFrame(for address: CellAddress, text: String) -> NSRect {
    let cell = geometry.rect(of: address)
    let style = model.style(at: address)
    var frame = cell.insetBy(dx: 1, dy: 1)
    frame.origin.x += 2
    frame.size.width -= 2
    // 折り返すセルは幅をそのままに、中身に合わせて下へ伸ばす
    if style.wraps {
      frame.size.height = max(frame.height, Self.wrappedHeight(text, style: style, width: cell.width) - 2)
      return frame
    }
    let lines = text.components(separatedBy: "\n")
    let widest = lines.map { ($0 as NSString).size(withAttributes: [.font: Self.font]).width }.max() ?? 0
    frame.size.width = max(frame.width, min(widest + 16, 600))
    let lineHeight = ceil(Self.font.ascender - Self.font.descender) + 2
    if lines.count > 1 {
      frame.size.height = max(frame.height, CGFloat(lines.count) * lineHeight + 2)
    } else {
      frame.origin.y += (frame.height - 18) / 2
      frame.size.height = 18
    }
    return frame
  }

  /// 編集を終える。commit なら入力を確かめずにそのまま入れる。move があれば入力先を動かす
  func finishEditing(commit: Bool, move: (rows: Int, columns: Int)? = nil) {
    guard let field = editor, let address = editingAddress else { return }
    // 先に状態を消す（入力欄を外すときにもう一度ここへ来ても、二重に確定しないように）
    editor = nil
    editingAddress = nil
    pointing = nil
    let text = field.stringValue
    field.delegate = nil
    window?.makeFirstResponder(self)
    field.removeFromSuperview()
    if commit {
      model.setInput(text, at: address, wrapping: insertedLineBreak)
    } else {
      model.formulaText = model.input(at: model.active)
    }
    if let move { model.advance(rows: move.rows, columns: move.columns) }
    needsDisplay = true
    scrollToActive()
  }

  /// 参照を入れる場所。入れたばかりの参照の直後にカーソルがあればその参照を置き換え、
  /// 演算子・「(」・「,」の直後なら、カーソルの位置に入れる。それ以外（数式でない、文字の途中）は nil
  func referenceTarget(in text: NSTextView) -> NSRange? {
    let string = text.string as NSString
    let caret = text.selectedRange()
    guard string.hasPrefix("="), caret.length == 0, caret.location > 0 else { return nil }
    if let pointing, caret.location == NSMaxRange(pointing.textRange) { return pointing.textRange }
    let previous = string.substring(with: NSRange(location: caret.location - 1, length: 1))
    return "=+-*/^&(,:<>".contains(previous) ? caret : nil
  }

  func insertReference(_ range: CellRange, start: CellAddress, replacing target: NSRange, in text: NSTextView) {
    let reference = range.description
    isInsertingReference = true
    text.insertText(reference, replacementRange: target)
    isInsertingReference = false
    pointing = Pointing(start: start, range: range, textRange: NSRange(location: target.location, length: (reference as NSString).length))
    needsDisplay = true
  }

  func controlTextDidChange(_ notification: Notification) {
    // 自分で文字を打ったら、次のクリックは参照の置き換えではなく、新しい参照の追加か確定になる
    if !isInsertingReference, pointing != nil {
      pointing = nil
      needsDisplay = true
    }
    guard let field = editor, let address = editingAddress else { return }
    model.formulaText = field.stringValue
    field.frame = editorFrame(for: address, text: field.stringValue)
  }

  func controlTextDidEndEditing(_ notification: Notification) {
    finishEditing(commit: true)
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    switch selector {
    case #selector(insertNewline(_:)):
      let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
      finishEditing(commit: true, move: (shift ? -1 : 1, 0))
    case #selector(insertTab(_:)): finishEditing(commit: true, move: (0, 1))
    case #selector(insertBacktab(_:)): finishEditing(commit: true, move: (0, -1))
    case #selector(cancelOperation(_:)): finishEditing(commit: false)
    // option + Return（Excel の Alt + Enter）でセルの中で改行する
    case #selector(insertNewlineIgnoringFieldEditor(_:)), #selector(insertLineBreak(_:)):
      textView.insertText("\n", replacementRange: textView.selectedRange())
      insertedLineBreak = true
    case #selector(moveUp(_:)) where isTypingNewValue: finishEditing(commit: true, move: (-1, 0))
    case #selector(moveDown(_:)) where isTypingNewValue: finishEditing(commit: true, move: (1, 0))
    case #selector(moveLeft(_:)) where isTypingNewValue: finishEditing(commit: true, move: (0, -1))
    case #selector(moveRight(_:)) where isTypingNewValue: finishEditing(commit: true, move: (0, 1))
    default: return false
    }
    return true
  }
}
