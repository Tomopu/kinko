import AppKit
import KinkoCore

final class SheetCellsView: NSView, NSMenuItemValidation {
  let model: SheetEditorModel
  let geometry: SheetGeometry

  static let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
  /// 目盛りの線。自分で引く罫線（黒）と見分けられるよう、Excel と同じくらいの薄いグレーにする
  static let gridLineColor = NSColor(name: "KinkoGridLine") { appearance in
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      ? NSColor(white: 0.24, alpha: 1) : NSColor(white: 0.86, alpha: 1)
  }
  static let handleSize: CGFloat = 7

  enum Drag {
    case selecting
    /// つまみを引っぱっている。target は今マウスのあるセル
    case filling(target: CellAddress)
    /// 数式の入力中に、参照するセルをクリック・ドラッグで指している
    case pointing
  }

  /// 数式の入力中にクリックで入れた参照。続けてクリックやドラッグをすると、この参照を置き換える
  struct Pointing {
    var start: CellAddress
    var range: CellRange
    /// 入力欄の文字列の中で、入れた参照の位置
    var textRange: NSRange
  }

  private(set) var pointing: Pointing?
  private var isInsertingReference = false

  private(set) var drag: Drag?
  private(set) var editor: NSTextField?
  private(set) var editingAddress: CellAddress?
  /// 打ち始めて入力しているとき（ダブルクリックや F2 で直しているときではなく）。矢印キーで確定して隣へ移る（Excel と同じ）
  private var isTypingNewValue = false
  /// 入力中にセルの中で改行した（option + Return）。確定するとき折り返しもオンにする
  private var insertedLineBreak = false

  init(model: SheetEditorModel, geometry: SheetGeometry) {
    self.model = model
    self.geometry = geometry
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  override var isOpaque: Bool { true }

  // MARK: マウス

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    // 数式を入力中で、演算子や「(」の直後なら、クリックしたセルの参照を入れる（Excel と同じ）
    if let text = editor?.currentEditor() as? NSTextView, let target = referenceTarget(in: text) {
      let cell = geometry.cell(at: point)
      insertReference(CellRange(cell), start: cell, replacing: target, in: text)
      drag = .pointing
      return
    }
    finishEditing(commit: true)
    window?.makeFirstResponder(self)
    if handleRect.insetBy(dx: -3, dy: -3).contains(point) {
      drag = .filling(target: geometry.cell(at: point))
      return
    }
    let cell = geometry.cell(at: point)
    if event.clickCount == 2 {
      model.select(cell)
      beginEditing(replacing: false)
      return
    }
    model.select(cell, extending: event.modifierFlags.contains(.shift))
    drag = .selecting
  }

  override func mouseDragged(with event: NSEvent) {
    autoscroll(with: event)
    let cell = geometry.cell(at: convert(event.locationInWindow, from: nil))
    switch drag {
    case .selecting:
      model.select(cell, extending: true)
    case .filling:
      drag = .filling(target: cell)
      needsDisplay = true
    case .pointing:
      guard let pointing, let text = editor?.currentEditor() as? NSTextView else { break }
      insertReference(CellRange(pointing.start, cell), start: pointing.start, replacing: pointing.textRange, in: text)
    case nil:
      break
    }
  }

  override func mouseUp(with event: NSEvent) {
    if case .filling = drag, let preview = fillPreview {
      // option を押しながら離すと、数が 1 つだけでも連番にする（Excel の Ctrl に当たる）
      model.fill(preview.direction, count: preview.count, incrementsSingleNumbers: event.modifierFlags.contains(.option))
    }
    drag = nil
    needsDisplay = true
  }

  /// つまみをどこまで引っぱったか。選択範囲から縦と横のどちらへ多くはみ出したかで向きを決める
  var fillPreview: (direction: FillDirection, count: Int, range: CellRange)? {
    guard case .filling(let target) = drag else { return nil }
    let source = model.selection
    let rows = target.row > source.end.row ? target.row - source.end.row : (target.row < source.start.row ? target.row - source.start.row : 0)
    let columns =
      target.column > source.end.column
      ? target.column - source.end.column : (target.column < source.start.column ? target.column - source.start.column : 0)
    if rows == 0 && columns == 0 { return nil }
    if abs(rows) >= abs(columns) {
      let edge = CellAddress(row: rows > 0 ? source.end.row + rows : source.start.row + rows, column: rows > 0 ? source.end.column : source.start.column)
      return (rows > 0 ? .down : .up, abs(rows), CellRange(rows > 0 ? source.start : source.end, edge))
    }
    let edge = CellAddress(row: columns > 0 ? source.end.row : source.start.row, column: columns > 0 ? source.end.column + columns : source.start.column + columns)
    return (columns > 0 ? .right : .left, abs(columns), CellRange(columns > 0 ? source.start : source.end, edge))
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    finishEditing(commit: true)
    let cell = geometry.cell(at: convert(event.locationInWindow, from: nil))
    if !model.selection.contains(cell) { model.select(cell) }
    return SheetMenus.cellMenu(target: self)
  }

  // MARK: キーボード

  override func keyDown(with event: NSEvent) {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let shift = flags.contains(.shift)
    if flags.contains(.command) || flags.contains(.control) {
      super.keyDown(with: event)
      return
    }
    switch event.specialKey {
    case .upArrow: model.move(rows: -1, columns: 0, extending: shift)
    case .downArrow: model.move(rows: 1, columns: 0, extending: shift)
    case .leftArrow: model.move(rows: 0, columns: -1, extending: shift)
    case .rightArrow: model.move(rows: 0, columns: 1, extending: shift)
    case .carriageReturn, .enter: model.advance(rows: shift ? -1 : 1, columns: 0)
    case .tab: model.advance(rows: 0, columns: 1)
    case .backTab: model.advance(rows: 0, columns: -1)
    case .delete, .deleteForward, .backspace: model.clearSelection()
    case .f2: beginEditing(replacing: false)
    case .pageDown: model.move(rows: visibleRowCount, columns: 0, extending: shift)
    case .pageUp: model.move(rows: -visibleRowCount, columns: 0, extending: shift)
    default:
      guard let characters = event.characters, !characters.isEmpty,
        characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.value < 0xF700 })
      else {
        super.keyDown(with: event)
        return
      }
      // 文字を打ったら、セルの中身を置き換えて入力を始める。キーは入力欄へ渡すので、日本語入力の変換もそのまま効く
      beginEditing(replacing: true)
      editor?.currentEditor()?.keyDown(with: event)
      return
    }
    scrollToActive()
  }

  private var visibleRowCount: Int { max(1, geometry.row(at: visibleRect.maxY) - geometry.row(at: visibleRect.minY) - 1) }

  func scrollToActive() {
    scrollToVisible(geometry.rect(of: model.active).insetBy(dx: -2, dy: -2))
  }

  // MARK: メニューの操作（編集メニューと右クリック）

  @objc func copy(_ sender: Any?) { model.copy() }
  @objc func cut(_ sender: Any?) { model.cut() }
  @objc func paste(_ sender: Any?) { model.paste() }
  @objc func delete(_ sender: Any?) { model.clearSelection() }
  @objc override func selectAll(_ sender: Any?) {
    model.select(
      range: CellRange(CellAddress(row: 0, column: 0), CellAddress(row: CellAddress.maxRows - 1, column: CellAddress.maxColumns - 1)),
      active: CellAddress(row: 0, column: 0))
  }
  @objc func undo(_ sender: Any?) { model.undo() }
  @objc func redo(_ sender: Any?) { model.redo() }

  @objc func insertRowsAbove(_ sender: Any?) { model.insertRows(below: false) }
  @objc func insertRowsBelow(_ sender: Any?) { model.insertRows(below: true) }
  @objc func deleteSelectedRows(_ sender: Any?) { model.deleteRows() }
  @objc func insertColumnsLeft(_ sender: Any?) { model.insertColumns(right: false) }
  @objc func insertColumnsRight(_ sender: Any?) { model.insertColumns(right: true) }
  @objc func deleteSelectedColumns(_ sender: Any?) { model.deleteColumns() }
  @objc func insertCellsShiftingDown(_ sender: Any?) { model.insertCells(.vertical) }
  @objc func insertCellsShiftingRight(_ sender: Any?) { model.insertCells(.horizontal) }
  @objc func deleteCellsShiftingUp(_ sender: Any?) { model.deleteCells(.vertical) }
  @objc func deleteCellsShiftingLeft(_ sender: Any?) { model.deleteCells(.horizontal) }
  @objc func clearFormats(_ sender: Any?) { model.clearFormats() }

  func validateMenuItem(_ item: NSMenuItem) -> Bool {
    switch item.action {
    case #selector(undo(_:)): return model.canUndo
    case #selector(redo(_:)): return model.canRedo
    case #selector(paste(_:)):
      return NSPasteboard.general.availableType(from: [CellClip.type, .string]) != nil
    case #selector(copy(_:)), #selector(cut(_:)), #selector(delete(_:)): return model.usedSelection != nil
    default: return true
    }
  }
}

// MARK: - 入力

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
  private func referenceTarget(in text: NSTextView) -> NSRange? {
    let string = text.string as NSString
    let caret = text.selectedRange()
    guard string.hasPrefix("="), caret.length == 0, caret.location > 0 else { return nil }
    if let pointing, caret.location == NSMaxRange(pointing.textRange) { return pointing.textRange }
    let previous = string.substring(with: NSRange(location: caret.location - 1, length: 1))
    return "=+-*/^&(,:<>".contains(previous) ? caret : nil
  }

  private func insertReference(_ range: CellRange, start: CellAddress, replacing target: NSRange, in text: NSTextView) {
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
