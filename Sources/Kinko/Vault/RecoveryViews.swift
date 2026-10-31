import KinkoCore
import SwiftUI

/// 復旧コードを見せて、控えてもらう画面。控えたと確かめるまで閉じられない
struct RecoveryCodeView: View {
  @Environment(VaultSession.self) private var session
  let code: RecoveryCode
  @State private var hasWrittenDown = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label("復旧コードを控えてください", systemImage: "key.viewfinder").font(.title2.bold())
      Text("この金庫はこの Mac 専用です。Mac を失くしたり、壊れたり、初期化したりしたときは、このコードがないと二度と開けません。")
        .fixedSize(horizontal: false, vertical: true)
      Text(code.description)
        // 欠けて見えると控え間違えるので、縮めも省略もせず 1 行で出す（29 文字が画面の幅に入る大きさ）
        .font(.system(size: 18, weight: .semibold, design: .monospaced))
        .fixedSize()
        .textSelection(.enabled)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
      Text(
        """
        紙に書いて、Mac とは別の安全な場所にしまってください。写真やメモアプリ、クラウドには残さないでください（このコードがあれば、パスワードなしで開けます）。
        パスワードを変えたり、この Mac 専用にし直したりすると、新しいコードに変わります。
        """
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      Toggle("紙などに控えました", isOn: $hasWrittenDown)
      HStack {
        Spacer()
        Button("完了") { session.acknowledgeRecoveryCode() }
          .keyboardShortcut(.defaultAction)
          .disabled(!hasWrittenDown)
      }
    }
    .padding(24)
    .frame(width: 440)
    .interactiveDismissDisabled()
  }
}

/// 復旧コードで開き、新しいパスワードを決め直す画面
struct RecoveryView: View {
  @Environment(VaultSession.self) private var session
  let url: URL

  @State private var code = ""
  @State private var password = ""
  @State private var confirmation = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("復旧コードで開く").font(.title2.bold())
      Text(url.lastPathComponent).foregroundStyle(.secondary)
      TextField("復旧コード（XXXX-XXXX-…）", text: $code)
        .font(.system(size: 14, design: .monospaced))
        .textFieldStyle(.roundedBorder)
        .autocorrectionDisabled()
      PasswordField(title: "新しいパスワード", text: $password)
      PasswordField(title: "確認のためもう一度", text: $confirmation)
      Text("開いたあと、この Mac の新しい鍵と新しいパスワードで作り直し、新しい復旧コードを出します。今の復旧コードは使えなくなります。")
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      if let message = session.errorMessage {
        Text(message).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        Button("戻る") { session.cancelRecovery() }
        Spacer()
        if session.isBusy { ProgressView().controlSize(.small) }
        Button("開く", action: submit)
          .keyboardShortcut(.defaultAction)
          .disabled(session.isBusy || code.isEmpty || password.isEmpty)
      }
    }
    .padding(28)
    .onSubmit(submit)
  }

  private func submit() {
    guard !session.isBusy, !code.isEmpty, !password.isEmpty else { return }
    let code = code, password = password, confirmation = confirmation
    self.code = ""
    self.password = ""
    self.confirmation = ""
    Task { await session.recover(at: url, code: code, password: password, confirmation: confirmation) }
  }
}
