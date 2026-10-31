import KinkoCore
import SwiftUI

/// 設定画面の、パスワードを変えるフォーム。開いている金庫のパスワードを変える
struct ChangePasswordForm: View {
  @Environment(VaultSession.self) private var session

  @State private var current = ""
  @State private var new = ""
  @State private var confirmation = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      PasswordField(title: "今のパスワード", text: $current)
      PasswordField(title: "新しいパスワード", text: $new)
      PasswordField(title: "確認のためもう一度", text: $confirmation)
      Text(
        "金庫全体を新しい鍵で暗号化し直して保存します。編集中の内容も一緒に保存されます。Time Machine などに残っている以前のコピーは、古いパスワードのままです。"
          + (session.protection == .deviceBound ? "この Mac 専用の金庫なので、復旧コードも新しくなります。" : ""))
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      KeyChangeResult()

      HStack {
        Spacer()
        if session.isBusy { ProgressView().controlSize(.small) }
        Button("変更", action: submit)
          .keyboardShortcut(.defaultAction)
          .disabled(session.isBusy || new.isEmpty || current.isEmpty)
      }
    }
    .onSubmit(submit)
  }

  private func submit() {
    guard !session.isBusy, !new.isEmpty, !current.isEmpty else { return }
    let current = current, new = new, confirmation = confirmation
    // 入力欄の文字列はすぐ手放す
    self.current = ""
    self.new = ""
    self.confirmation = ""
    Task { await session.changePassword(current: current, new: new, confirmation: confirmation) }
  }
}

/// 設定画面での鍵の作り直しの結果（エラーか、終わったという知らせ）
struct KeyChangeResult: View {
  @Environment(VaultSession.self) private var session

  var body: some View {
    if let message = session.keyChangeError {
      Text(message).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
    } else if let message = session.keyChangeMessage {
      Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
    }
  }
}
