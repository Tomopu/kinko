import KinkoCore
import SwiftUI

/// 設定画面（⌘,）。金庫の守り方（この Mac 専用・Touch ID・間違えたときの削除）、開いている金庫のパスワードの変更、表示
struct SettingsView: View {
  @Environment(VaultSession.self) private var session
  enum Tab: String {
    case security
    case password
    case display
  }

  static let tabKey = "settingsTab"
  @AppStorage(SettingsView.tabKey) private var tab = Tab.security

  var body: some View {
    TabView(selection: $tab) {
      SecuritySettings()
        .tabItem { Label("セキュリティ", systemImage: "lock.shield") }
        .tag(Tab.security)
      PasswordSettings()
        .tabItem { Label("パスワード変更", systemImage: "key") }
        .tag(Tab.password)
      DisplaySettings()
        .tabItem { Label("表示", systemImage: "paintbrush") }
        .tag(Tab.display)
    }
    .frame(width: 480)
    .background(SettingsWindow.Tracker())
    .sheet(item: recoveryCode) { pending in
      RecoveryCodeView(code: pending.code)
    }
  }

  /// 設定画面で作り直したときの復旧コードは、設定画面の上に出す
  private var recoveryCode: Binding<VaultSession.PendingRecoveryCode?> {
    Binding(
      get: { session.pendingRecoveryCode.flatMap { $0.fromSettings ? $0 : nil } },
      set: { if $0 == nil { session.acknowledgeRecoveryCode() } })
  }
}

/// 見た目の設定。この Mac の Kinko 全体に効き、金庫を開いていなくても変えられる
private struct DisplaySettings: View {
  @AppStorage(SheetBackground.key) private var sheetBackground = SheetBackground.light

  var body: some View {
    Form {
      Section {
        Picker("ダークモードのときの表の背景", selection: $sheetBackground) {
          ForEach(SheetBackground.allCases, id: \.self) { Text($0.title) }
        }
        .pickerStyle(.radioGroup)
      } footer: {
        Text("白にすると、ダークモードでも表（セルと行・列の見出し）を Excel と同じ明るい見た目で表示します。ライトモードのときは常に白です。")
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .formStyle(.grouped)
    .frame(minHeight: 200)
  }
}

extension VaultSession.PendingRecoveryCode: Identifiable {
  var id: String { code.description }
}

/// 金庫の守り方。この Mac 専用・Touch ID は開いている金庫ごと、間違えたときの削除はこの Mac の Kinko 全体の設定
private struct SecuritySettings: View {
  @Environment(VaultSession.self) private var session
  /// 消す設定に切り替える前の確認で、選ぼうとしている回数
  @State private var pendingLimit: Int?
  /// この Mac 専用にする（true）か解除する（false）ために、パスワードを聞いている
  @State private var bindingRequest: Bool?

  var body: some View {
    Form {
      Section("開いている金庫") {
        if let protection = session.protection {
          LabeledContent("守り方") {
            Text(protection == .deviceBound ? "この Mac 専用" : "パスワードだけ（どの Mac でも開ける）")
          }
          ProtectionComparison(current: protection)
          HStack {
            Spacer()
            Button(protection == .deviceBound ? "どの Mac でも開けるように戻す…" : "この Mac 専用にする…") {
              bindingRequest = protection != .deviceBound
            }
            .disabled(protection == .password && !DeviceKeyStore.isSecureEnclaveAvailable)
          }
          Toggle("Touch ID で開く", isOn: touchID)
            .disabled(!DeviceKeyStore.isTouchIDAvailable || session.isBusy)
          Text(
            DeviceKeyStore.isTouchIDAvailable
              ? "パスワードの代わりに指で開けます。7 日に 1 回と、指紋を登録し直したあとはパスワードが必要です。"
              : "この Mac では Touch ID を使えません。"
          )
          .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          KeyChangeResult()
        } else {
          Text("金庫を開いているときに、その金庫の守り方を変えられます。")
            .foregroundStyle(.secondary)
        }
      }
      Section("パスワードを間違えたとき") {
        Picker("続けて間違えたら", selection: limit) {
          Text("金庫を削除しない").tag(0)
          ForEach(UnlockAttempts.limits, id: \.self) { count in
            Text("\(count) 回で金庫を削除する").tag(count)
          }
        }
        Text(
          """
          この Mac の Kinko で開こうとしたときだけ数え、正しいパスワードで開けたら数え直します。削除した金庫は元に戻せません（ゴミ箱にも入りません）。
          この Mac 専用の金庫では、この Mac の鍵も消すので、コピーやバックアップに残ったファイルもパスワードでは開けなくなります（復旧コードでは開けます）。\
          パスワードだけの金庫では、コピーされたファイルを別の道具で試されると防げません。
          """
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
    .formStyle(.grouped)
    // Form は中身の高さを外に伝えないので、説明文まで入る高さにしておく（足りないと下が切れてスクロールになる）
    .frame(minHeight: 700)
    .sheet(item: Binding(get: { bindingRequest.map(BindingRequest.init) }, set: { bindingRequest = $0?.bind })) { request in
      BindingSheet(bind: request.bind)
    }
    .alert(
      "パスワードを \(pendingLimit ?? 0) 回続けて間違えたら、金庫を削除しますか？",
      isPresented: Binding(get: { pendingLimit != nil }, set: { if !$0 { pendingLimit = nil } })
    ) {
      Button("削除する設定にする", role: .destructive) {
        session.eraseLimit = pendingLimit
        pendingLimit = nil
      }
      Button("キャンセル", role: .cancel) { pendingLimit = nil }
    } message: {
      Text("打ち間違いが続いたときや、ほかの人が試したときにも削除されます。大切な金庫は、バックアップがあることを確かめてから有効にしてください。")
    }
  }

  private var touchID: Binding<Bool> {
    Binding(get: { session.isTouchIDEnabled }, set: { enabled in Task { await session.setTouchID(enabled) } })
  }

  /// 消さない設定から消す設定へ変えるときだけ確認する（回数を変えるだけなら確認しない）
  private var limit: Binding<Int> {
    Binding(
      get: { session.eraseLimit ?? 0 },
      set: { count in
        if count == 0 {
          session.eraseLimit = nil
        } else if session.eraseLimit == nil {
          pendingLimit = count
        } else {
          session.eraseLimit = count
        }
      })
  }
}

/// 開いている金庫のパスワードを変える
private struct PasswordSettings: View {
  @Environment(VaultSession.self) private var session

  var body: some View {
    Group {
      if case .editing(let url) = session.phase {
        VStack(alignment: .leading, spacing: 12) {
          Text("「\(url.lastPathComponent)」のパスワードを変更").font(.headline)
          ChangePasswordForm()
        }
      } else {
        Text("金庫を開いているときに、その金庫のパスワードを変更できます。")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 120)
      }
    }
    .padding(20)
  }
}

/// メニューの「パスワードを変更…」。設定画面のパスワードのタブを開く
struct ChangePasswordMenuButton: View {
  @Environment(\.openSettings) private var openSettings
  @AppStorage(SettingsView.tabKey) private var tab = SettingsView.Tab.security
  let isEnabled: Bool

  var body: some View {
    Button("パスワードを変更…") {
      tab = .password
      openSettings()
    }
    .disabled(!isEnabled)
  }
}

private struct BindingRequest: Identifiable {
  var bind: Bool
  var id: Bool { bind }
}

/// この Mac 専用にする・解除する前に、今のパスワードを聞くシート
private struct BindingSheet: View {
  @Environment(VaultSession.self) private var session
  @Environment(\.dismiss) private var dismiss
  let bind: Bool
  @State private var password = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(bind ? "この Mac 専用にする" : "どの Mac でも開けるように戻す").font(.title2.bold())
      Text(
        bind
          ? "パスワードとこの Mac の鍵の両方で開く金庫に作り直し、復旧コードを出します。Mac を失くしたり初期化したりしたときは、復旧コードがないと開けません。ほかの Mac では開けなくなります。"
          : "パスワードだけで開ける金庫に作り直します。コピーされたファイルを、ほかの Mac でパスワードを試して開かれるおそれがあります。今の復旧コードは使えなくなります。"
      )
      .fixedSize(horizontal: false, vertical: true)
      PasswordField(title: "今のパスワード", text: $password)
      KeyChangeResult()
      HStack {
        Button("キャンセル") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Spacer()
        if session.isBusy { ProgressView().controlSize(.small) }
        Button(bind ? "この Mac 専用にする" : "戻す", action: submit)
          .keyboardShortcut(.defaultAction)
          .disabled(session.isBusy || password.isEmpty)
      }
    }
    .padding(24)
    .frame(width: 420)
    .onSubmit(submit)
  }

  private func submit() {
    guard !session.isBusy, !password.isEmpty else { return }
    let password = password
    self.password = ""
    Task {
      await session.setDeviceBound(bind, password: password)
      if session.keyChangeError == nil { dismiss() }
    }
  }
}
