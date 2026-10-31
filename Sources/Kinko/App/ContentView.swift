import AppKit
import SwiftUI

struct ContentView: View {
  @Environment(VaultSession.self) private var session

  var body: some View {
    // 鍵の画面は小さく、編集画面は広く開く。どちらも、全画面や最大化のときはウィンドウいっぱいに広がる
    // （KinkoApp の windowResizability(.contentSize) と組み合わせる。固定の大きさにすると、全画面で周りが黒く余る）
    switch session.phase {
    case .start:
      StartView().lockFrame()
    case .creating(let url):
      PasswordView(url: url, isCreating: true).lockFrame()
    case .unlocking(let url):
      PasswordView(url: url, isCreating: false).lockFrame()
    case .recovering(let url):
      RecoveryView(url: url).lockFrame()
    case .editing(let url):
      WorkspaceView(url: url)
        .frame(minWidth: 640, minHeight: 420)
        .background(WindowFitter(size: CGSize(width: 960, height: 620), mode: .grow))
        .sheet(item: recoveryCode) { pending in
          RecoveryCodeView(code: pending.code).environment(session)
        }
    }
  }

  /// 作ったときや復旧したときの復旧コードは、編集画面の上に出す（設定画面で作り直したときは設定画面の上）
  private var recoveryCode: Binding<VaultSession.PendingRecoveryCode?> {
    Binding(
      get: { session.pendingRecoveryCode.flatMap { $0.fromSettings ? nil : $0 } },
      set: { if $0 == nil { session.acknowledgeRecoveryCode() } })
  }

  static let lockSize = CGSize(width: 440, height: 420)
}

extension View {
  /// 鍵の画面の大きさ。普段は小さく、ウィンドウが大きいときは真ん中に置く
  fileprivate func lockFrame() -> some View {
    frame(maxWidth: ContentView.lockSize.width, maxHeight: ContentView.lockSize.height)
      .frame(
        minWidth: ContentView.lockSize.width, idealWidth: ContentView.lockSize.width, maxWidth: .infinity,
        minHeight: ContentView.lockSize.height, idealHeight: ContentView.lockSize.height, maxHeight: .infinity)
      .background(WindowFitter(size: ContentView.lockSize, mode: .shrink))
  }
}

/// 画面が切り替わったときに、ウィンドウの大きさを一度だけ合わせる。
/// 編集画面では、狭ければ広げる（最小サイズのままだと編集画面としては狭い）。鍵の画面では、広ければ元の小ささに戻す。
/// 全画面や最大化しているときは、利用者が決めた大きさなので動かさない（全画面のウィンドウを動かすと表示が崩れる）
private struct WindowFitter: NSViewRepresentable {
  enum Mode {
    /// 少なくとも size まで広げる
    case grow
    /// size より大きければ size に戻す
    case shrink
  }

  let size: CGSize
  let mode: Mode

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      guard let window = view.window, !window.styleMask.contains(.fullScreen), !window.isZoomed else { return }
      let current = window.contentRect(forFrameRect: window.frame).size
      let target: CGSize
      switch mode {
      case .grow:
        guard current.width < size.width || current.height < size.height else { return }
        target = CGSize(width: max(current.width, size.width), height: max(current.height, size.height))
      case .shrink:
        guard current.width > size.width || current.height > size.height else { return }
        target = size
      }
      var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: target))
      // 左上の位置を保ったまま、画面からはみ出さない範囲で合わせる
      frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
      if let visible = window.screen?.visibleFrame {
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
      }
      window.setFrame(frame, display: true, animate: true)
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct StartView: View {
  @Environment(VaultSession.self) private var session

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "lock.shield")
        .font(.system(size: 48))
        .foregroundStyle(.secondary)
      Text("Kinko").font(.largeTitle.bold())
      Text("ファイルは暗号化して保存します。\nパスワードを忘れると復元できません。")
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      if let notice = session.notice {
        Label(notice, systemImage: "trash")
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        Button("新しい金庫を作る…") { session.chooseNewFile() }
        Button("金庫を開く…") { session.chooseExistingFile() }
          .keyboardShortcut(.defaultAction)
      }
      .controlSize(.large)
    }
    .padding(32)
  }
}

private struct PasswordView: View {
  @Environment(VaultSession.self) private var session
  let url: URL
  let isCreating: Bool

  @State private var password = ""
  @State private var confirmation = ""
  @State private var bindToThisMac = false
  @State private var triedTouchID = false
  @State private var isShowingComparison = false

  private var options: VaultSession.UnlockOptions { session.unlockOptions }
  /// この Mac 専用の金庫なのに、この Mac に鍵がない（ほかの Mac か、鍵を消した）
  private var isMissingDeviceKey: Bool { !isCreating && options.protection == .deviceBound && !options.hasDeviceKey }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(isCreating ? "新しい金庫のパスワード" : "パスワードを入力")
        .font(.title2.bold())
      Text(url.lastPathComponent).foregroundStyle(.secondary)

      if isMissingDeviceKey {
        Label("この金庫はこの Mac 専用ですが、この Mac の鍵が見つかりません。復旧コードで開いてください。", systemImage: "key.slash")
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        PasswordField(title: "パスワード", text: $password)
      }
      if isCreating {
        PasswordField(title: "確認のためもう一度", text: $confirmation)
        Text("忘れた場合データを復元できません。半角の英数字と記号が使えます。ランダムに選んだ単語を 4〜5 個つなげた、長いパスフレーズがおすすめです。")
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        HStack {
          Toggle("この Mac でだけ開けるようにする", isOn: $bindToThisMac)
            .disabled(!DeviceKeyStore.isSecureEnclaveAvailable)
          Button("違いを見る", systemImage: "questionmark.circle") { isShowingComparison = true }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .hoverLabel("この Mac 専用にした場合との違い")
            .popover(isPresented: $isShowingComparison) {
              ProtectionComparison()
                .padding(16)
                .frame(width: 460)
            }
        }
      }
      if let message = session.errorMessage {
        Text(message).foregroundStyle(.red)
      }
      if !isCreating, let remaining = session.remainingBeforeErase {
        Label(
          remaining == 1 ? "次に間違えると、この金庫は削除されます。" : "あと \(remaining) 回間違えると、この金庫は削除されます。",
          systemImage: "exclamationmark.triangle.fill"
        )
        .foregroundStyle(.orange)
        .fixedSize(horizontal: false, vertical: true)
      }

      HStack {
        Button("キャンセル") { session.cancel() }
        if !isCreating, options.protection == .deviceBound {
          Button("復旧コードで開く…") { session.beginRecovery(url) }
        }
        Spacer()
        if session.isBusy { ProgressView().controlSize(.small) }
        if !isCreating, options.canUseTouchID {
          Button {
            Task { await session.unlockWithTouchID(at: url) }
          } label: {
            Image(systemName: "touchid")
          }
          .hoverLabel("Touch ID で開く")
          .disabled(session.isBusy)
        }
        if !isMissingDeviceKey {
          Button(isCreating ? "作成" : "開く", action: submit)
            .keyboardShortcut(.defaultAction)
            .disabled(session.isBusy || password.isEmpty)
        }
      }
    }
    .padding(28)
    .onSubmit(submit)
    .task {
      // Touch ID が使えるなら、開いた時点で一度だけ指紋を求める（取り消せばパスワードで開ける）
      guard !isCreating, options.canUseTouchID, !triedTouchID else { return }
      triedTouchID = true
      await session.unlockWithTouchID(at: url)
    }
  }

  private func submit() {
    guard !session.isBusy, !password.isEmpty else { return }
    let password = password, confirmation = confirmation
    // 入力欄の文字列はすぐ手放す
    self.password = ""
    self.confirmation = ""
    Task {
      if isCreating {
        await session.create(at: url, password: password, confirmation: confirmation, bindToThisMac: bindToThisMac)
      } else {
        await session.unlock(at: url, password: password)
      }
    }
  }
}
