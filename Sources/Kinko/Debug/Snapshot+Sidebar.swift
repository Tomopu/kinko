#if DEBUG
import AppKit
import KinkoCore
import SwiftUI

extension Snapshot {
  /// サイドバー（フォルダ名のクリックでの開け閉め、コピー・ペースト・複製、下の帯）、
  /// 長いシート名、新規ファイルを作るときに設定のウィンドウが閉じるかを確かめる
  static func checkSidebar(url: URL, directory: URL) {
    var workspace = Workspace()
    let folder = WorkspaceItem.folder("仕事", children: [.file("議事録.txt", text: "社外秘")])
    try? workspace.add(folder, to: nil)
    for number in 1...24 {
      try? workspace.add(.file("メモ \(number).md", text: "\(number)"), to: nil)
    }
    let inner = folder.children![0].id
    let first = workspace.items[1].id

    let session = VaultSession()
    session.preview(phase: .editing(url), workspace: workspace, selection: first)
    render(session, size: CGSize(width: 760, height: 420), appearance: .aqua, to: directory.appending(path: "sidebar-light.png")) { window in
      guard let outline = findView(NSOutlineView.self, in: window.contentView) else { return print("snapshot: outline not found") }
      // 一番上の金庫の行の次がフォルダ「仕事」。名前をクリックすると開き、もう一度クリックすると閉じる
      let closedRows = outline.numberOfRows
      click(outline, row: 1, in: window)
      let openedRows = outline.numberOfRows
      let selected = session.selection == folder.id
      click(outline, row: 1, in: window)
      let closedAgain = outline.numberOfRows == closedRows
      session.selection = nil
      RunLoop.main.run(until: Date().addingTimeInterval(0.3))
      click(outline, row: 2, in: window)
      let fileSelected = session.selection == first
      print(
        "snapshot: folder click opened=\(openedRows == closedRows + 1) selected=\(selected) closed=\(closedAgain)"
          + " fileSelected=\(fileSelected) offscreen=\(window.frame.origin == OffscreenWindow.origin)")

      // コピーして別の場所へ貼り付ける、同じ場所に複製する。貼り付けた項目のあるフォルダは開く
      session.copyItem(first)
      session.selection = folder.id
      session.pasteItem()
      let pasted = session.selection.flatMap { session.workspace.item($0) }
      RunLoop.main.run(until: Date().addingTimeInterval(0.3))
      let shown = outline.numberOfRows == closedRows + 2
      session.duplicate(inner)
      let duplicated = session.selection.flatMap { session.workspace.item($0) }
      session.setText("書き換えた", of: duplicated?.id ?? inner)
      print(
        "snapshot: copy pasted=\(pasted?.name ?? "-")(\(pasted?.text ?? "-")) shown=\(shown)"
          + " duplicated=\(duplicated?.name ?? "-") original=\(session.text(of: inner))")
      session.selection = first
    }
    render(session, size: CGSize(width: 760, height: 420), appearance: .darkAqua, to: directory.appending(path: "sidebar-dark.png"))

    // シート名が長くても折り返さない
    let names = ["2026年度 予算（確定版）", "売上の集計", "Sheet3", "取引先の一覧（関東）", "メモ"]
    let book = WorkspaceItem.sheet("予算.xlsx", workbook: Workbook(sheets: names.map { Sheet(name: $0) }))
    let sheets = VaultSession()
    sheets.preview(phase: .editing(url), workspace: Workspace(items: [book]), selection: book.id)
    render(sheets, size: CGSize(width: 760, height: 360), appearance: .aqua, to: directory.appending(path: "sheet-tabs.png"))

    // ダークモードでも、既定では表の部分を白で描く。設定で黒にもできる
    let defaults = UserDefaults.standard
    let saved = defaults.string(forKey: SheetBackground.key)
    defaults.removeObject(forKey: SheetBackground.key)
    render(sheets, size: CGSize(width: 760, height: 360), appearance: .darkAqua, to: directory.appending(path: "sheet-dark-white.png"))
    defaults.set(SheetBackground.dark.rawValue, forKey: SheetBackground.key)
    render(sheets, size: CGSize(width: 760, height: 360), appearance: .darkAqua, to: directory.appending(path: "sheet-dark-dark.png"))
    defaults.set(saved, forKey: SheetBackground.key)
    let tab = defaults.string(forKey: SettingsView.tabKey)
    defaults.set(SettingsView.Tab.display.rawValue, forKey: SettingsView.tabKey)
    renderView(SettingsView().environment(sheets), appearance: .darkAqua, to: directory.appending(path: "settings-display.png"))
    defaults.set(tab, forKey: SettingsView.tabKey)

    // 設定を開いたまま新規ファイルを作ると、設定のウィンドウが閉じる
    let settings = OffscreenWindow(
      contentRect: NSRect(origin: OffscreenWindow.origin, size: CGSize(width: 480, height: 700)),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    settings.isReleasedWhenClosed = false
    settings.contentView = NSHostingView(rootView: SettingsView().environment(session))
    settings.orderFrontRegardless()
    render(session, size: CGSize(width: 760, height: 420), appearance: .aqua, to: directory.appending(path: "sidebar-new-file.png")) { _ in
      let wasOpen = settings.isVisible
      NotificationCenter.default.post(name: .kinkoNewFile, object: nil)
      RunLoop.main.run(until: Date().addingTimeInterval(0.5))
      print("snapshot: settings closed on new file=\(wasOpen && !settings.isVisible)")
    }
    settings.orderOut(nil)
  }

  /// リストの行の真ん中をクリックする。押したあとの離す操作を先に積んでおき、リストが離されるのを待ち続けないようにする
  private static func click(_ outline: NSOutlineView, row: Int, in window: NSWindow) {
    let rect = outline.rect(ofRow: row)
    let point = outline.convert(CGPoint(x: rect.minX + 60, y: rect.midY), to: nil)
    func event(_ type: NSEvent.EventType) -> NSEvent? {
      NSEvent.mouseEvent(
        with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
    }
    guard let down = event(.leftMouseDown), let up = event(.leftMouseUp) else { return }
    (window as? OffscreenWindow)?.pretendsKey = true
    defer { (window as? OffscreenWindow)?.pretendsKey = false }
    NSApp.postEvent(down, atStart: false)
    NSApp.postEvent(up, atStart: false)
    // アプリのイベントの列から取り出して配る（NSApp.run は動いていないので自分で回す）
    while let next = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.1), inMode: .default, dequeue: true) {
      NSApp.sendEvent(next)
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
  }
}
#endif
