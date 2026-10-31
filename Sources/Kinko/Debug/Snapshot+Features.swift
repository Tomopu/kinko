#if DEBUG
import AppKit
import KinkoCore
import PDFKit
import SwiftUI

extension Snapshot {
  /// 表のフォント、PDF の表示、マウスを重ねたときの札、守り方の違いの表を描き出して確かめる
  static func checkFeatures(url: URL, directory: URL) {
    // 表: 見出しを明朝の 18 ポイント、注意書きを 9 ポイントにする
    var sheet = Sheet(name: "Sheet1")
    for (a1, input) in [("A1", "2026 年の予定"), ("A2", "旅行"), ("B2", "120000"), ("A3", "※ 小さな注意書き")] {
      sheet[CellAddress(a1)!] = input
    }
    sheet[style: CellAddress("A1")!].fontName = "Hiragino Mincho ProN"
    sheet[style: CellAddress("A1")!].fontSize = 18
    sheet[style: CellAddress("A1")!].bold = true
    sheet[style: CellAddress("A3")!].fontSize = 9
    sheet.columnWidths[0] = 160
    let table = WorkspaceItem.sheet("予定.xlsx", workbook: Workbook(sheets: [sheet]))

    // PDF: 2 ページの PDF を作って取り込む
    let pdf = samplePDF()
    let imported = try? FileTransfer.importFile(named: "資料.pdf", data: pdf)
    let exported = imported.flatMap { try? FileTransfer.exportData(for: $0) }
    print("snapshot: pdf imported=\(imported?.isPDF == true) exportedSame=\(exported == pdf)")

    var workspace = Workspace()
    try? workspace.add(table, to: nil)
    if let imported { try? workspace.add(imported, to: nil) }

    let session = VaultSession()
    session.preview(phase: .editing(url), workspace: workspace, selection: table.id)
    render(session, size: CGSize(width: 960, height: 420), appearance: .aqua, to: directory.appending(path: "sheet-fonts.png")) { window in
      guard let grid = findView(SheetGridView.self, in: window.contentView) else { return print("snapshot: grid not found") }
      let model = grid.model
      // 大きな文字の行は高く、小さな文字の行は既定の高さのまま
      let tall = grid.geometry.height(of: 0) > SheetGeometry.rowHeight
      let small = grid.geometry.height(of: 2) == SheetGeometry.rowHeight
      // 書式バーの操作: B2 を 1 段階ずつ大きくして 14 にし、フォントを戻す
      model.select(range: CellRange(CellAddress("B2")!), active: CellAddress("B2")!)
      model.stepFontSize(up: true)
      model.stepFontSize(up: true)
      let stepped = model.style(at: CellAddress("B2")!).fontSize == 14
      model.setFontSize(11)
      let reset = model.style(at: CellAddress("B2")!).fontSize == nil
      // 折り返しの 3 つの見せ方と、取り消し・やり直し
      model.select(range: CellRange(CellAddress("A2")!), active: CellAddress("A2")!)
      model.setInput("旅行の計画（行き先と日程と予算）", at: CellAddress("A2")!)
      model.setOverflow(.clip)
      let clipped = model.activeOverflow == .clip && !model.style(at: CellAddress("A2")!).wraps
      model.setOverflow(.wrap)
      let wrapped = model.activeOverflow == .wrap && !model.style(at: CellAddress("A2")!).clips
      model.undo()
      let undone = model.activeOverflow == .clip
      model.redo()
      let redone = model.activeOverflow == .wrap
      model.setOverflow(.clip)
      print("snapshot: overflow clipped=\(clipped) wrapped=\(wrapped) undone=\(undone) redone=\(redone)")
      // .xlsx に書き出して読み戻しても、フォントが残る
      let back = (try? XLSX.read(XLSX.write(model.workbook) { _, _ in .empty }))?.sheets[0]
      let roundTrip = back?[style: CellAddress("A1")!].fontName == "Hiragino Mincho ProN" && back?[style: CellAddress("A1")!].fontSize == 18
      print("snapshot: fonts tall=\(tall) small=\(small) stepped=\(stepped) reset=\(reset) roundTrip=\(roundTrip)")
      model.select(range: CellRange(CellAddress("A1")!), active: CellAddress("A1")!)
    }

    if let imported {
      let viewing = VaultSession()
      viewing.preview(phase: .editing(url), workspace: workspace, selection: imported.id)
      for appearance in [NSAppearance.Name.aqua, .darkAqua] {
        let suffix = appearance == .aqua ? "light" : "dark"
        render(viewing, size: CGSize(width: 860, height: 560), appearance: appearance, to: directory.appending(path: "pdf-\(suffix).png")) { window in
          guard let view = findView(PDFView.self, in: window.contentView) else { return print("snapshot: pdf view not found") }
          print("snapshot: pdf pages=\(view.document?.pageCount ?? 0)")
        }
      }
    }

    renderView(HoverLabelView(text: "新規ファイル（⌘N）"), appearance: .aqua, to: directory.appending(path: "hover-label.png"))
    renderView(
      VStack(spacing: 8) {
        OptionPalette(options: SheetEditorModel.TextOverflow.allCases, selected: .wrap, name: \.title, icon: { OverflowIcon(overflow: $0) }) { _ in }
        OptionPalette(options: [KinkoCore.VerticalAlignment.top, .center, .bottom], selected: .center, name: \.rawValue, icon: {
          Image(systemName: FormatBar.verticalSymbol($0))
        }) { _ in }
      }
      .padding(10).background(Color(nsColor: .windowBackgroundColor)),
      appearance: .aqua, to: directory.appending(path: "option-palettes.png"))
    for (protection, name) in [(UnlockedVault.Protection?.none, "comparison"), (.deviceBound, "comparison-device")] {
      renderView(
        ProtectionComparison(current: protection).padding(16).frame(width: 460).background(Color(nsColor: .windowBackgroundColor)),
        appearance: .aqua, to: directory.appending(path: "\(name).png"))
    }
  }

  /// アップデートの確認の画面。KINKO_SNAPSHOT_NETWORK=1 のときだけ、本物の GitHub にも問い合わせる
  static func checkUpdates(directory: URL) {
    let current = AppVersion("0.13.0")!
    let release = Release(
      version: AppVersion("0.14.0")!, title: "Kinko 0.14.0",
      notes: "## 変更\n- PDF の中を検索できるようにした\n- 表の行と列を固定できるようにした\n\n中身の形式が 8 になります。一度保存すると 0.13 では開けません。",
      page: URL(string: "https://github.com/Tomopu/Kinko/releases/tag/v0.14.0")!,
      dmg: URL(string: "https://github.com/Tomopu/Kinko/releases/download/v0.14.0/Kinko-0.14.0.dmg")!)
    for (state, name) in [
      (UpdateChecker.State.available(release), "update-available"), (.upToDate(current), "update-latest"),
      (.failed(UpdateError.network("オフライン").localizedDescription), "update-failed"),
    ] {
      let checker = UpdateChecker(current: current, repository: "Tomopu/Kinko", state: state)
      renderView(UpdateView().environment(checker).background(Color(nsColor: .windowBackgroundColor)), appearance: .aqua, to: directory.appending(path: "\(name).png"))
    }

    guard ProcessInfo.processInfo.environment["KINKO_SNAPSHOT_NETWORK"] == "1" else { return }
    // リリースのあるリポジトリでは新しい版が見つかり、リリースのないリポジトリでは最新と答える
    for repository in ["swiftlang/swift-markdown", "Tomopu/Kinko"] {
      let checker = UpdateChecker(current: AppVersion("0.0.1"), repository: repository)
      wait { await checker.check() }
      print("snapshot: update \(repository) -> \(checker.state)")
    }
  }

  /// 見出しと本文のある 2 ページの PDF
  private static func samplePDF() -> Data {
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
    for page in 1...2 {
      context.beginPDFPage(nil)
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
      ("契約書の控え（\(page) ページ目）" as NSString).draw(
        at: NSPoint(x: 60, y: 760), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 22)])
      ("この PDF は金庫の中にだけあり、ディスクには暗号化された形でしか残りません。" as NSString).draw(
        at: NSPoint(x: 60, y: 720), withAttributes: [.font: NSFont.systemFont(ofSize: 13)])
      NSGraphicsContext.restoreGraphicsState()
      context.endPDFPage()
    }
    context.closePDF()
    return data as Data
  }
}
#endif
