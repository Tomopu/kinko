import KinkoCore
import SwiftUI

/// 設定画面（⌘,）。パスワードを間違えたときの扱いと、開いている金庫のパスワードの変更
struct SettingsView: View {
  enum Tab: String {
    case security
    case password
  }

  static let tabKey = "settingsTab"
  @AppStorage(SettingsView.tabKey) private var tab = Tab.security

  var body: some View {
    TabView(selection: $tab) {
      SecuritySettings()
        .tabItem { Label("セキュリティ", systemImage: "lock.shield") }
        .tag(Tab.security)
      PasswordSettings()
        .tabItem { Label("パスワード", systemImage: "key") }
        .tag(Tab.password)
    }
    .frame(width: 460)
  }
}

/// パスワードを続けて間違えたときに、金庫のファイルを消すかどうか
private struct SecuritySettings: View {
  @Environment(VaultSession.self) private var session
  /// 消す設定に切り替える前の確認で、選ぼうとしている回数
  @State private var pendingLimit: Int?

  var body: some View {
    Form {
      Picker("パスワードを間違えたとき", selection: limit) {
        Text("金庫を削除しない").tag(0)
        ForEach(UnlockAttempts.limits, id: \.self) { count in
          Text("\(count) 回続けて間違えたら金庫を削除する").tag(count)
        }
      }
      Text(
        """
        この Mac の Kinko で開こうとしたときだけ数え、正しいパスワードで開けたら数え直します。\
        削除した金庫は元に戻せません（ゴミ箱にも入りません）。
        ファイルをコピーされて別の道具で試された場合は防げません。また、Time Machine などのバックアップに残っているコピーは消えません。
        """
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
    .formStyle(.grouped)
    // Form は中身の高さを外に伝えないので、説明文まで入る高さにしておく（足りないと下が切れてスクロールになる）
    .frame(minHeight: 250)
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
