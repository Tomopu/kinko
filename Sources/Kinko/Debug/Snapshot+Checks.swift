#if DEBUG
import AppKit
import KinkoCore
import SwiftUI

/// チェックリスト・ウィンドウの大きさ・パスワードの変更の確認
extension Snapshot {
  /// チェック欄のクリック、Return でのリスト継続、「[]」の近道を、実際のエディタ部品に対して行う
  static func checkChecklist(url: URL, directory: URL) {
    let list = WorkspaceItem.file("買い物.md", text: "- [ ] 牛乳を買う\n- [x] 掃除\n\n本文")
    let session = VaultSession()
    session.preview(phase: .editing(url), workspace: Workspace(items: [list]), selection: list.id)
    render(session, size: CGSize(width: 860, height: 520), appearance: .aqua, to: directory.appending(path: "checklist-interaction.png")) { window in
      guard let textView = findView(NSTextView.self, in: window.contentView),
        let layoutManager = textView.layoutManager, let container = textView.textContainer
      else { return print("snapshot: text view not found") }
      window.makeFirstResponder(textView)
      let length = (textView.string as NSString).length
      textView.setSelectedRange(NSRange(location: length, length: 0))
      RunLoop.main.run(until: Date().addingTimeInterval(0.3))

      // 1 行目の ☐ をクリックする
      let glyph = layoutManager.glyphIndexForCharacter(at: 2)
      let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
      let point = textView.convert(NSPoint(x: rect.midX + textView.textContainerOrigin.x, y: rect.midY + textView.textContainerOrigin.y), to: nil)
      if let click = NSEvent.mouseEvent(
        with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
        context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
      {
        textView.mouseDown(with: click)
      }
      RunLoop.main.run(until: Date().addingTimeInterval(0.3))
      print("snapshot: toggled=\(textView.string.hasPrefix("- [x] 牛乳を買う")) cursorKept=\(textView.selectedRange().location == length)")

      // 2 行目の末尾で Return → 「- [ ] 」が続く。何も書かずにもう一度 Return → 記号が消える
      let secondLineEnd = (textView.string as NSString).range(of: "掃除").upperBound
      textView.setSelectedRange(NSRange(location: secondLineEnd, length: 0))
      textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
      let continued = textView.string.contains("- [x] 掃除\n- [ ] ")
      textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
      let ended = textView.string.contains("- [x] 掃除\n\n")
      print("snapshot: continued=\(continued) ended=\(ended)")

      // 行頭で「[]」と空白を打つと「- [ ] 」になる
      textView.insertText("[]", replacementRange: textView.selectedRange())
      textView.insertText(" ", replacementRange: textView.selectedRange())
      RunLoop.main.run(until: Date().addingTimeInterval(0.3))
      textView.insertText("電池", replacementRange: textView.selectedRange())
      textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
      RunLoop.main.run(until: Date().addingTimeInterval(0.3))
      print("snapshot: shortcut=\(textView.string.contains("\n- [ ] 電池")) text=\(textView.string.debugDescription)")
    }
  }

  /// 最大化・全画面のときにウィンドウを動かさないこと、普段は編集画面で広げてロックで戻すことを確かめる
  static func checkWindowSizing(url: URL, workspace: Workspace, directory: URL) {
    func makeWindow(_ session: VaultSession) -> NSWindow {
      let window = NSWindow(
        contentRect: NSRect(origin: CGPoint(x: 80, y: 80), size: ContentView.lockSize),
        styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
      window.contentView = NSHostingView(rootView: ContentView().environment(session))
      window.orderFrontRegardless()
      RunLoop.main.run(until: Date().addingTimeInterval(1))
      return window
    }
    func save(_ window: NSWindow, _ name: String) {
      if let image = captureWindow(window.windowNumber) {
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: directory.appending(path: name))
      }
    }

    // 普段：編集画面で広がり、ロックすると元の小ささに戻る
    let normal = VaultSession()
    let window = makeWindow(normal)
    normal.preview(phase: .editing(url), workspace: workspace)
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    let grew = window.contentRect(forFrameRect: window.frame).size
    normal.lock()
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    let shrank = window.contentRect(forFrameRect: window.frame).size
    window.orderOut(nil)

    // 最大化：鍵の画面がウィンドウいっぱいに広がり、編集画面へ切り替えても、ロックしても大きさが変わらない
    let zoomedSession = VaultSession()
    let zoomed = makeWindow(zoomedSession)
    zoomed.zoom(nil)
    RunLoop.main.run(until: Date().addingTimeInterval(1))
    let zoomedFrame = zoomed.frame
    save(zoomed, "window-zoomed-start.png")
    zoomedSession.preview(phase: .editing(url), workspace: workspace)
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    save(zoomed, "window-zoomed-editing.png")
    let keptEditing = zoomed.frame == zoomedFrame
    zoomedSession.lock()
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    let keptLocked = zoomed.frame == zoomedFrame
    zoomed.orderOut(nil)
    print("snapshot: window grew=\(grew) shrank=\(shrank) zoomed=\(zoomedFrame.size) keptEditing=\(keptEditing) keptLocked=\(keptLocked)")
  }

  /// パスワード変更を実際のファイルで通しで行う
  static func checkPasswordChange(directory: URL) {
    let folder = directory.appending(path: "tmp-vaults")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let file = folder.appending(path: "変更.kinko")
    let session = VaultSession()
    wait { await session.create(at: file, password: "old passphrase 1", confirmation: "old passphrase 1") }
    wait { await session.changePassword(current: "wrong passphrase", new: "new passphrase 2", confirmation: "new passphrase 2") }
    let rejectedWrongCurrent = session.passwordChangeError == "今のパスワードが違います。"
    wait { await session.changePassword(current: "old passphrase 1", new: "new passphrase 2", confirmation: "new passphrase 2") }
    let data = (try? Data(contentsOf: file)) ?? Data()
    let opensWithNew = (try? UnlockedVault.open(data, password: "new passphrase 2")) != nil
    let rejectsOld = (try? UnlockedVault.open(data, password: "old passphrase 1")) == nil
    print("snapshot: wrongCurrentRejected=\(rejectedWrongCurrent) opensWithNew=\(opensWithNew) rejectsOld=\(rejectsOld)")

    UserDefaults.standard.set(SettingsView.Tab.password.rawValue, forKey: SettingsView.tabKey)
    renderView(SettingsView().environment(session), appearance: .aqua, to: directory.appending(path: "settings-password.png"))
    UserDefaults.standard.set(SettingsView.Tab.security.rawValue, forKey: SettingsView.tabKey)
    renderView(SettingsView().environment(session), appearance: .aqua, to: directory.appending(path: "settings-security.png"))
    let unlocking = VaultSession()
    unlocking.preview(phase: .unlocking(file))
    render(unlocking, size: ContentView.lockSize, appearance: .aqua, to: directory.appending(path: "unlock-light.png"))
  }

  /// パスワードを決めた回数だけ続けて間違えると、金庫のファイルが消えることを実際のファイルで確かめる。
  /// 回数の記録は、本物の設定を汚さないよう使い捨ての UserDefaults に置く
  static func checkEraseAfterFailures(directory: URL) {
    let folder = directory.appending(path: "tmp-erase")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let suite = "kinko-snapshot-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    let file = folder.appending(path: "消える.kinko")
    let session = VaultSession(defaults: defaults)
    wait { await session.create(at: file, password: "right passphrase", confirmation: "right passphrase") }
    session.lock()
    session.eraseLimit = 5

    // 2 回間違えてから正しく開くと数え直す
    session.beginUnlocking(file)
    for _ in 1...2 { wait { await session.unlock(at: file, password: "wrong passphrase") } }
    let warnedAfterTwo = session.remainingBeforeErase == 3
    wait { await session.unlock(at: file, password: "right passphrase") }
    session.lock()
    session.beginUnlocking(file)
    let resetAfterSuccess = session.remainingBeforeErase == nil

    // 続けて 4 回間違えると「次で削除」、5 回目で消える
    for _ in 1...4 { wait { await session.unlock(at: file, password: "wrong passphrase") } }
    let warnedLast = session.remainingBeforeErase == 1
    render(session, size: ContentView.lockSize, appearance: .aqua, to: directory.appending(path: "unlock-warning.png"))
    let existedBefore = FileManager.default.fileExists(atPath: file.path)
    wait { await session.unlock(at: file, password: "wrong passphrase") }
    let erased = existedBefore && !FileManager.default.fileExists(atPath: file.path) && session.phase == .start
    render(session, size: ContentView.lockSize, appearance: .aqua, to: directory.appending(path: "start-erased.png"))

    // 設定は次に開いたときも残っている
    let remembered = VaultSession(defaults: defaults).eraseLimit == 5
    print("snapshot: erase warnedAfterTwo=\(warnedAfterTwo) resetAfterSuccess=\(resetAfterSuccess) warnedLast=\(warnedLast) erased=\(erased) notice=\(session.notice ?? "-") remembered=\(remembered)")
  }
}
#endif
