import SwiftUI

@main
struct KinkoApp: App {
  @State private var session = VaultSession()
  @State private var updates = UpdateChecker()

  init() {
    #if DEBUG
    Snapshot.runIfRequested()
    UpdateInstaller.runInstallTestIfRequested()
    #endif
  }

  var body: some Scene {
    Window("Kinko", id: "main") {
      ContentView()
        .environment(session)
    }
    // 鍵の画面は大きなウィンドウにも広がるようにしたので、最初に開く大きさはここで決める
    .defaultSize(width: ContentView.lockSize.width, height: ContentView.lockSize.height)
    .windowResizability(.contentSize)
    .commands {
      CommandGroup(after: .appInfo) {
        CheckForUpdatesButton(checker: updates)
      }
      CommandGroup(replacing: .newItem) {
        Button("新規ファイル…") { NotificationCenter.default.post(name: .kinkoNewFile, object: nil) }
          .keyboardShortcut("n")
          .disabled(!isEditing)
        Button("新規の表…") { NotificationCenter.default.post(name: .kinkoNewSheet, object: nil) }
          .keyboardShortcut("n", modifiers: [.command, .option])
          .disabled(!isEditing)
        Button("新規フォルダ…") { NotificationCenter.default.post(name: .kinkoNewFolder, object: nil) }
          .keyboardShortcut("n", modifiers: [.command, .shift])
          .disabled(!isEditing)
        Divider()
        Button("読み込む…") { session.importFiles() }
          .keyboardShortcut("i", modifiers: [.command, .shift])
          .disabled(!isEditing)
        Button("書き出す…") { session.exportSelection() }
          .keyboardShortcut("e", modifiers: [.command, .shift])
          .disabled(!isEditing)
      }
      CommandGroup(replacing: .saveItem) {
        Button("保存") { session.save() }
          .keyboardShortcut("s")
          .disabled(!session.isDirty)
        Button("ロック") { NotificationCenter.default.post(name: .kinkoLock, object: nil) }
          .keyboardShortcut("l")
          .disabled(!isEditing)
        Divider()
        ChangePasswordMenuButton(isEnabled: isEditing)
      }
    }

    Window("アップデート", id: "update") {
      UpdateView()
        .environment(updates)
        .environment(session)
    }
    .windowResizability(.contentSize)

    Settings {
      SettingsView()
        .environment(session)
    }
  }

  private var isEditing: Bool {
    if case .editing = session.phase { true } else { false }
  }
}
