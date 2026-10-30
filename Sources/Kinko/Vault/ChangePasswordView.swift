import KinkoCore
import SwiftUI

/// パスワードを変えるシート
struct ChangePasswordView: View {
  @Environment(VaultSession.self) private var session

  @State private var current = ""
  @State private var new = ""
  @State private var confirmation = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("パスワードを変更").font(.title2.bold())
      PasswordField(title: "今のパスワード", text: $current)
      PasswordField(title: "新しいパスワード", text: $new)
      PasswordField(title: "確認のためもう一度", text: $confirmation)
      Text("金庫全体を新しい鍵で暗号化し直して保存します。編集中の内容も一緒に保存されます。Time Machine などに残っている以前のコピーは、古いパスワードのままです。")
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      if let message = session.passwordChangeError {
        Text(message).foregroundStyle(.red)
      }

      HStack {
        Button("キャンセル") { session.isChangingPassword = false }
          .keyboardShortcut(.cancelAction)
        Spacer()
        if session.isBusy { ProgressView().controlSize(.small) }
        Button("変更", action: submit)
          .keyboardShortcut(.defaultAction)
          .disabled(session.isBusy || new.isEmpty || current.isEmpty)
      }
    }
    .padding(24)
    .frame(width: 400)
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
