import AppKit
import KinkoCore
import SwiftUI

/// 「アップデートを確認…」のウィンドウ。調べた結果と、新しい版があれば変更内容とダウンロードのボタンを出す
struct UpdateView: View {
  @Environment(UpdateChecker.self) private var checker

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
      Text(
        """
        入れ替え方：Kinko を終了してから、ダウンロードした DMG を開き、Kinko をアプリケーションフォルダへドラッグして「置き換える」を選びます。\
        金庫のファイル・この Mac の鍵・設定はアプリの外にあるので、そのまま使えます。
        初めて開くときは、「システム設定 > プライバシーとセキュリティ」の「このまま開く」がもう一度必要です。
        """
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      HStack {
        Button("リリースのページ") { NSWorkspace.shared.open(release.page) }
        Spacer()
        Button(release.dmg == nil ? "ダウンロードページを開く" : "DMG をダウンロード") {
          NSWorkspace.shared.open(release.dmg ?? release.page)
        }
        .keyboardShortcut(.defaultAction)
      }
    }
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
