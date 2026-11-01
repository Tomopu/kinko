import AppKit
import KinkoCore
import SwiftUI

/// 「アップデートを確認…」のウィンドウ。調べた結果と、新しい版があれば変更内容とダウンロードのボタンを出す
struct UpdateView: View {
  @Environment(UpdateChecker.self) private var checker
  @Environment(VaultSession.self) private var session

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      switch checker.state {
      case .idle, .checking:
        HStack(spacing: 10) {
          ProgressView().controlSize(.small)
          Text("新しい版を確認しています…")
        }
        .frame(maxWidth: .infinity, minHeight: 80)
      case .upToDate(let version):
        Label("Kinko \(version.description) は最新の版です", systemImage: "checkmark.circle.fill")
          .font(.title3.bold())
          .foregroundStyle(.green)
        footer
      case .available(let release):
        available(release)
      case .failed(let message):
        Label("確認できませんでした", systemImage: "exclamationmark.triangle.fill")
          .font(.title3.bold())
          .foregroundStyle(.orange)
        Text(message).fixedSize(horizontal: false, vertical: true)
        footer
      }
    }
    .padding(24)
    .frame(width: 460)
  }

  private func available(_ release: Release) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("新しい版 \(release.version.description) があります", systemImage: "arrow.down.circle.fill")
        .font(.title3.bold())
      Text("今の版は \(checker.current?.description ?? "不明") です。").foregroundStyle(.secondary)
      if !release.notes.isEmpty {
        Text("変更内容").font(.headline)
        ScrollView {
          // リリースの説明は外から来る文字なので、リンクや書式として解釈せず、そのまま見せる
          Text(verbatim: release.notes)
            .font(.callout)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        // 短ければ中身の高さに縮め、長ければ 200pt でスクロールにする
        .frame(maxHeight: 200)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
      }
      if let blocker = checker.automaticInstallBlocker(for: release) {
        manual(release, reason: blocker)
      } else {
        automatic(release)
      }
    }
  }

  /// 自動で入れ替える。ダウンロードと確認のあと、再起動して入れ替える
  @ViewBuilder
  private func automatic(_ release: Release) -> some View {
    switch checker.install {
    case .idle:
      note(
        """
        「アップデート」を押すと、新しい版をダウンロードして配布元の署名を確かめ、Kinko を再起動して入れ替えます。\
        金庫のファイル・この Mac の鍵・設定はそのまま使えます。再起動すると金庫はロックされます。
        """)
      HStack {
        Button("リリースのページ") { NSWorkspace.shared.open(release.page) }
        Spacer()
        Button("アップデート") { checker.startInstall(release) }
          .keyboardShortcut(.defaultAction)
      }
    case .working(let message, let fraction):
      VStack(alignment: .leading, spacing: 6) {
        Text(message).font(.callout)
        if let fraction {
          ProgressView(value: fraction)
        } else {
          ProgressView().progressViewStyle(.linear)
        }
      }
      HStack {
        Spacer()
        Button("キャンセル") { checker.cancelInstall() }
      }
    case .ready(let prepared):
      Label("Kinko \(prepared.version.description) を入れる準備ができました", systemImage: "checkmark.seal.fill")
        .foregroundStyle(.green)
      if session.isDirty {
        note("保存していない変更があります。保存してから再起動します。")
      } else {
        note("再起動すると、新しい版に入れ替わって開き直します。金庫はロックされます。")
      }
      HStack {
        Button("あとで") { checker.cancelInstall() }
        Spacer()
        Button(session.isDirty ? "保存して再起動" : "再起動して入れ替える") { restart() }
          .keyboardShortcut(.defaultAction)
      }
    case .failed(let message):
      Text(message)
        .foregroundStyle(.red)
        .fixedSize(horizontal: false, vertical: true)
      manual(release, reason: nil)
    case .rejected:
      Text(UpdateError.badSignature.localizedDescription)
        .foregroundStyle(.red)
        .fixedSize(horizontal: false, vertical: true)
      // 差し替えられた DMG かもしれないので、ダウンロードのボタンは出さない
      note("配布元のリリースが書き換えられているおそれがあります。しばらくしてからもう一度確認するか、配布元に問い合わせてください。")
      HStack {
        Button("リリースのページ") { NSWorkspace.shared.open(release.page) }
        Spacer()
        Button("OK") { checker.cancelInstall() }
      }
    }
  }

  /// 保存していない変更があれば先に保存し、保存できなければ止める（エラーは金庫の画面に出る）
  private func restart() {
    if session.isDirty { session.save() }
    guard !session.isDirty else { return }
    checker.restartToInstall()
  }

  /// 手で入れてもらう。DMG をダウンロードして置き換える
  @ViewBuilder
  private func manual(_ release: Release, reason: String?) -> some View {
    if let reason {
      note(reason)
    }
    note(
      """
      入れ替え方：Kinko を終了してから、ダウンロードした DMG を開き、Kinko をアプリケーションフォルダへドラッグして「置き換える」を選びます。\
      金庫のファイル・この Mac の鍵・設定はアプリの外にあるので、そのまま使えます。
      初めて開くときは、「システム設定 > プライバシーとセキュリティ」の「このまま開く」がもう一度必要です。
      """)
    HStack {
      Button("リリースのページ") { NSWorkspace.shared.open(release.page) }
      Spacer()
      Button(release.dmg == nil ? "ダウンロードページを開く" : "DMG をダウンロード") {
        NSWorkspace.shared.open(release.dmg ?? release.page)
      }
      .keyboardShortcut(.defaultAction)
    }
  }

  private func note(_ text: String) -> some View {
    Text(text)
      .font(.callout)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var footer: some View {
    HStack {
      Spacer()
      Button("もう一度確認") { Task { await checker.check() } }
    }
  }
}

/// アプリのメニューの「アップデートを確認…」。ウィンドウを開いて、そのたびに調べ直す
struct CheckForUpdatesButton: View {
  @Environment(\.openWindow) private var openWindow
  let checker: UpdateChecker

  var body: some View {
    Button("アップデートを確認…") {
      openWindow(id: "update")
      Task { await checker.check() }
    }
  }
}
