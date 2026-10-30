#if DEBUG
import AppKit
import KinkoCore
import SwiftUI

/// 表のエディタの確認
extension Snapshot {
  static func sampleBudget() -> WorkspaceItem {
    var sheet = Sheet(name: "10月")
    let rows = [
      ["日付", "曜日", "項目", "金額", "税込", "", "税率"],
      ["2026/10/01", "木", "食費", "1200", "=ROUND(D2*(1+$G$2),0)", "", "10%"],
      ["2026/10/02", "金", "交通費", "460"],
      ["2026/10/03", "土", "日用品", "980"],
      [],
      ["合計", "", "", "=SUM(D2:D5)"],
      ["平均", "", "", "=ROUND(AVERAGE(D2:D5),0)"],
      ["件数", "", "", "=COUNT(D2:D5)&\"件\""],
    ]
    for (r, row) in rows.enumerated() {
      for (c, input) in row.enumerated() { sheet[CellAddress(row: r, column: c)] = input }
    }
    sheet.columnWidths[0] = 104
    sheet.columnWidths[1] = 56
    sheet[CellAddress("A10")!] = "※ 税込は G2 の税率で計算する（はみ出して表示される長いメモ）"
    // 見出しは太字・中央揃え・背景色、金額は通貨、表全体に格子の罫線、合計の行は太字
    var header = CellStyle()
    header.bold = true
    header.alignment = .center
    header.fillColor = CellColor(hex: "DDEBF7")
    for row in 0...4 {
      for column in 0...4 {
        let address = CellAddress(row: row, column: column)
        var style = row == 0 ? header : CellStyle()
        style.borders = CellBorders(edges: .all)
        if row > 0, column >= 3 { style.numberFormat = .currency(decimals: 0) }
        if row > 0, column == 1 { style.alignment = .center }
        sheet[style: address] = style
      }
    }
    var total = CellStyle()
    total.bold = true
    total.numberFormat = .currency(decimals: 0)
    total.borders = CellBorders(top: .thin, bottom: BorderLine(style: .double))
    sheet[style: CellAddress("D6")!] = total
    var label = CellStyle()
    label.bold = true
    sheet[style: CellAddress("A6")!] = label
    var rate = CellStyle()
    rate.textColor = CellColor(hex: "C00000")
    rate.fillColor = CellColor(hex: "FFF2CC")
    sheet[style: CellAddress("G2")!] = rate
    // 折り返して上揃えにした長いメモ（2 行目が自動で高くなる）
    sheet[CellAddress("F1")!] = "メモ"
    sheet[style: CellAddress("F1")!] = header
    sheet[CellAddress("F2")!] = "長いメモは折り返して、セルの中に全部表示できる"
    var memo = CellStyle()
    memo.wraps = true
    memo.verticalAlignment = .top
    sheet[style: CellAddress("F2")!] = memo
    sheet.columnWidths[5] = 130
    return .sheet("家計簿.xlsx", workbook: Workbook(sheets: [sheet, Sheet(name: "11月")]))
  }

  /// 表の操作を、実際のグリッド部品に対して行う：入力、つまみでの複製、行の挿入と取り消し
  static func checkSheet(url: URL, directory: URL) {
    let budget = sampleBudget()
    var workspace = Workspace()
    try? workspace.add(.folder("仕事"), to: nil)
    try? workspace.add(.file("メモ.md"), to: nil)
    try? workspace.add(budget, to: nil)

    for appearance in [NSAppearance.Name.darkAqua] {
      let session = VaultSession()
      session.preview(phase: .editing(url), workspace: workspace, selection: budget.id)
      render(session, size: CGSize(width: 960, height: 560), appearance: appearance, to: directory.appending(path: "sheet-dark.png"))
      // 一番狭いウィンドウ（サイドバーを除くと 420pt ほど）でも書式バーが収まるか
      render(
        NSHostingView(rootView: SheetEditor(workbook: .constant(budget.sheet!))), size: CGSize(width: 420, height: 300),
        appearance: .aqua, to: directory.appending(path: "sheet-narrow.png"))
    }

    let session = VaultSession()
    session.preview(phase: .editing(url), workspace: workspace, selection: budget.id)
    render(session, size: CGSize(width: 960, height: 560), appearance: .aqua, to: directory.appending(path: "sheet-interaction.png")) { window in
      guard let cells = findView(SheetCellsView.self, in: window.contentView),
        let grid = findView(SheetGridView.self, in: window.contentView)
      else { return print("snapshot: grid not found") }
      let model = grid.model
      @MainActor func point(_ a1: String, dx: CGFloat = 0, dy: CGFloat = 0) -> NSPoint {
        let rect = grid.geometry.rect(of: CellAddress(a1)!)
        return cells.convert(NSPoint(x: rect.midX + dx, y: rect.midY + dy), to: nil)
      }
      @MainActor func mouse(_ type: NSEvent.EventType, _ location: NSPoint, modifiers: NSEvent.ModifierFlags = [], clicks: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(
          with: type, location: location, modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber,
          context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
      }
      @MainActor func click(_ a1: String, shift: Bool = false) {
        cells.mouseDown(with: mouse(.leftMouseDown, point(a1), modifiers: shift ? .shift : []))
        cells.mouseUp(with: mouse(.leftMouseUp, point(a1)))
      }
      /// つまみ（選択範囲の右下）を target のセルまで引っぱる
      @MainActor func dragHandle(of corner: String, to target: String) {
        let rect = grid.geometry.rect(of: CellAddress(corner)!)
        let handle = cells.convert(NSPoint(x: rect.maxX - 1, y: rect.maxY - 1), to: nil)
        cells.mouseDown(with: mouse(.leftMouseDown, handle))
        cells.mouseDragged(with: mouse(.leftMouseDragged, point(target)))
        cells.mouseUp(with: mouse(.leftMouseUp, point(target)))
      }
      @MainActor func type(_ text: String, then command: Selector = #selector(NSResponder.insertNewline(_:))) {
        let first = String(text.prefix(1))
        cells.keyDown(
          with: NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: first, charactersIgnoringModifiers: first, isARepeat: false, keyCode: 0)!)
        guard let editor = window.firstResponder as? NSTextView else { return print("snapshot: editor not focused") }
        // 撮影用のウィンドウはキー入力を受け取れないので、残りは入力欄へ直接入れる
        if editor.string.isEmpty { editor.insertText(first, replacementRange: editor.selectedRange()) }
        editor.insertText(String(text.dropFirst()), replacementRange: editor.selectedRange())
        editor.doCommand(by: command)
      }
      @MainActor func input(_ a1: String) -> String { model.input(at: CellAddress(a1)!) }
      @MainActor func shown(_ a1: String) -> String { model.displayText(at: CellAddress(a1)!) }

      window.makeFirstResponder(cells)
      // 日付と曜日の 2 列を選び、つまみで 1 行下へ広げる
      click("A4")
      click("B4", shift: true)
      dragHandle(of: "B4", to: "B5")
      let filledSeries = input("A5") == "2026/10/04" && input("B5") == "日"

      // 打ち込みと Return
      click("C5")
      type("書籍", then: #selector(NSResponder.insertTab(_:)))
      type("1500")
      let typed = input("C5") == "書籍" && input("D5") == "1500" && model.active == CellAddress("D6")!
      let total = shown("D6")

      // 数式をつまみで複製すると、相対参照だけがずれる
      click("E2")
      dragHandle(of: "E2", to: "E5")
      let copiedFormula = input("E3") == "=ROUND(D3*(1+$G$2),0)" && model.value(at: CellAddress("E5")!) == .number(1650)

      // 行の挿入で数式が追従し、取り消しで戻る（編集メニューと同じ経路で送る）
      click("A2")
      cells.insertRowsAbove(nil)
      let inserted = input("D7") == "=SUM(D3:D6)"
      // 撮影用のウィンドウはキーウィンドウにならないので、NSApp.sendAction ではなくこのウィンドウの応答チェーンへ送る
      window.firstResponder?.tryToPerform(#selector(SheetCellsView.undo(_:)), with: nil)
      let undone = input("D6") == "=SUM(D2:D5)" && input("A2") == "2026/10/01"

      let saved = session.workbook(of: budget.id).sheets[0][CellAddress("D5")!] == "1500" && session.isDirty

      // 数式の入力中に、セルをドラッグして参照を入れる
      click("D9")
      cells.keyDown(
        with: NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
          context: nil, characters: "=", charactersIgnoringModifiers: "=", isARepeat: false, keyCode: 0)!)
      if let editor = window.firstResponder as? NSTextView {
        if editor.string.isEmpty { editor.insertText("=", replacementRange: editor.selectedRange()) }
        editor.insertText("SUM(", replacementRange: editor.selectedRange())
        cells.mouseDown(with: mouse(.leftMouseDown, point("D2")))
        cells.mouseDragged(with: mouse(.leftMouseDragged, point("D5")))
        cells.mouseUp(with: mouse(.leftMouseUp, point("D5")))
        editor.insertText(")", replacementRange: editor.selectedRange())
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
      }
      let pointed = input("D9") == "=SUM(D2:D5)" && shown("D9") == "4140"

      // 太字の切り替え、検索、並べ替えと取り消し、集計
      click("C2")
      click("C5", shift: true)
      model.toggle(\.bold)
      let bolded = (2...5).allSatisfy { model.style(at: CellAddress("C\($0)")!).bold }
      model.toggle(\.bold)
      let found = model.find("書籍") && model.active == CellAddress("C5")!
      click("D2")
      click("A5", shift: true)
      model.sort(ascending: false)
      let sorted = input("A2") == "2026/10/04" && input("D2") == "1500" && model.style(at: CellAddress("D2")!).numberFormat == .currency(decimals: 0)
      model.undo()
      let summary = model.summary.map { "\($0.sum)/\($0.count)" } ?? "nil"
      // セルの中で改行して確定すると、折り返しがオンになり、行が高くなる
      let rowBefore = grid.geometry.height(of: 11)
      click("C12")
      cells.keyDown(
        with: NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
          context: nil, characters: "1", charactersIgnoringModifiers: "1", isARepeat: false, keyCode: 0)!)
      if let editor = window.firstResponder as? NSTextView {
        if editor.string.isEmpty { editor.insertText("1", replacementRange: editor.selectedRange()) }
        editor.insertText(" 行目", replacementRange: editor.selectedRange())
        editor.doCommand(by: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)))
        editor.insertText("2 行目", replacementRange: editor.selectedRange())
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
      }
      let wrapped = input("C12") == "1 行目\n2 行目" && model.style(at: CellAddress("C12")!).wraps
        && grid.geometry.height(of: 11) > rowBefore
      let memoRowTall = grid.geometry.height(of: 1) > SheetGeometry.rowHeight

      // 行見出しの境目をドラッグして高さを変え、ダブルクリックで自動に戻す
      var resized = false
      if let header = findView(SheetRowHeaderView.self, in: window.contentView) {
        let border = header.convert(NSPoint(x: 20, y: grid.geometry.y(of: 14)), to: nil)
        header.mouseDown(with: mouse(.leftMouseDown, border))
        header.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: border.x, y: border.y - 30)))
        header.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: border.x, y: border.y - 30)))
        let dragged = grid.geometry.height(of: 13) == SheetGeometry.rowHeight + 30
        header.mouseDown(with: mouse(.leftMouseDown, header.convert(NSPoint(x: 20, y: grid.geometry.y(of: 14)), to: nil), clicks: 2))
        resized = dragged && grid.geometry.height(of: 13) == SheetGeometry.rowHeight
      }
      // 罫線：線の種類と色を選んで外枠を引くと、外側の辺だけに付き、隣のセルの向かい合う辺は消える
      click("F1")
      click("F2", shift: true)
      model.borderLine = BorderLine(style: .mediumDashed, color: CellColor(hex: "0070C0"))
      model.setBorders(.outline)
      let f1 = model.style(at: CellAddress("F1")!).borders, f2 = model.style(at: CellAddress("F2")!).borders
      let e1 = model.style(at: CellAddress("E1")!).borders
      let outlined = f1.top == model.borderLine && f1.left == model.borderLine && f1.bottom == nil
        && f2.bottom == model.borderLine && e1.right == nil
      model.borderLine = BorderLine(style: .double)
      click("A12")
      click("C12", shift: true)
      model.setBorders(.bottom)
      let doubled = model.style(at: CellAddress("B12")!).borders.bottom?.style == .double
      print("snapshot: borders outlined=\(outlined) doubled=\(doubled)")
      renderView(BorderPanel(model: model), appearance: .aqua, to: directory.appending(path: "border-panel.png"))
      print("snapshot: wrap wrapped=\(wrapped) memoRowTall=\(memoRowTall) resized=\(resized)")
      print("snapshot: format pointed=\(pointed) bolded=\(bolded) found=\(found) sorted=\(sorted) summary=\(summary) shownCurrency=\(shown("D2"))")
      click("D2")
      click("D5", shift: true)
      print("snapshot: sheet filledSeries=\(filledSeries) typed=\(typed) total=\(total) copiedFormula=\(copiedFormula) inserted=\(inserted) undone=\(undone) saved=\(saved)")
      
    }
  }
}
#endif
