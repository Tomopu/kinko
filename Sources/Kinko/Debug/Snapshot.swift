#if DEBUG
import AppKit
import KinkoCore
import SwiftUI

/// 開発用：`swift run Kinko --snapshot <出力先>` で主な画面を PNG に描き出して終了する。
/// 画面収録の権限がなくても、自分のウィンドウを自分で描けば見た目を確かめられる
@MainActor
enum Snapshot {
  static func runIfRequested() {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count else { return }
    let directory = URL(fileURLWithPath: arguments[index + 1])
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    NSApplication.shared.setActivationPolicy(.accessory)

    let url = URL(fileURLWithPath: "/tmp/個人用.kinko")
    var workspace = Workspace()
    let work = WorkspaceItem.folder("仕事", children: [.file("議事録 2026-10.txt"), .file("パスワード一覧.txt")])
    let note = WorkspaceItem.file("メモ.md", text: """
      # 引っ越しの手続き

      **期限**は *10 月末*。詳しくは[区役所のページ](https://example.com)を見る。

      ## やること
      - 転出届を出す
      - [x] 電気・ガスの解約
      - [ ] ~~固定電話~~ ネットの移転

      > 暗証番号はここに書かない。

      ```
      マイナンバーカードを持っていく
      ```

      `更新日` 2026-10-30
      """)
    try? workspace.add(work, to: nil)
    try? workspace.add(.folder("家計"), to: nil)
    try? workspace.add(note, to: nil)

    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
      let suffix = appearance == .aqua ? "light" : "dark"
      render(VaultSession(), size: ContentView.lockSize, appearance: appearance, to: directory.appending(path: "start-\(suffix).png"))

      let creating = VaultSession()
      creating.preview(phase: .creating(url))
      render(creating, size: ContentView.lockSize, appearance: appearance, to: directory.appending(path: "password-\(suffix).png")) { window in
        // パスワード欄を選ぶと、フィールドエディタが英字入力だけに制限されるか
        guard let field = findView(NSSecureTextField.self, in: window.contentView) else { return print("snapshot: secure field not found") }
        // SwiftUI のフォーカス（@FocusState）はキーウィンドウでないと更新されないことがある
        window.makeKey()
        window.makeFirstResponder(field)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let editor = window.firstResponder as? NSTextView
        print("snapshot: roman-only=\(editor?.inputContext?.allowedInputSourceLocales ?? []) key=\(window.isKeyWindow)")
      }

      let editing = VaultSession()
      editing.preview(phase: .editing(url), workspace: workspace, selection: note.id, isDirty: true)
      render(editing, size: CGSize(width: 860, height: 520), appearance: appearance, to: directory.appending(path: "workspace-\(suffix).png"))
    }

    // Markdown エディタの操作を試す：カーソルを見出しへ動かす、文字を打つ、日本語の変換中にする
    let typing = VaultSession()
    typing.preview(phase: .editing(url), workspace: workspace, selection: note.id, isDirty: true)
    render(typing, size: CGSize(width: 860, height: 520), appearance: .aqua, to: directory.appending(path: "markdown-interaction.png")) { window in
      guard let textView = findView(NSTextView.self, in: window.contentView) else { return print("snapshot: text view not found") }
      window.makeFirstResponder(textView)
      textView.setSelectedRange(NSRange(location: 2, length: 0))
      RunLoop.main.run(until: Date().addingTimeInterval(0.3))
      textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
      textView.insertText("\n\n## 打ち込んだ見出し\n**太字**も", replacementRange: textView.selectedRange())
      textView.setMarkedText("へんかんちゅう", selectedRange: NSRange(location: 7, length: 0), replacementRange: textView.selectedRange())
      RunLoop.main.run(until: Date().addingTimeInterval(0.3))
      print("snapshot: marked=\(textView.hasMarkedText()) bound=\(typing.text(of: note.id).hasSuffix("**太字**も"))")
    }

    checkChecklist(url: url, directory: directory)
    checkWindowSizing(url: url, workspace: workspace, directory: directory)
    checkSheet(url: url, directory: directory)
    checkPasswordChange(directory: directory)
    checkEraseAfterFailures(directory: directory)
    checkDeviceBound(directory: directory)
    checkFeatures(url: url, directory: directory)
    checkSidebar(url: url, directory: directory)
    checkUpdates(directory: directory)
    exit(0)
  }

  /// 非同期の処理を、終わるまでメインのループを回しながら待つ
  static func wait(_ work: @escaping @MainActor () async -> Void) {
    final class Flag { var done = false }
    let flag = Flag()
    Task { @MainActor in
      await work()
      flag.done = true
    }
    while !flag.done { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
  }

  static func renderView(_ view: some View, appearance: NSAppearance.Name, to url: URL) {
    let host = NSHostingView(rootView: view)
    render(host, size: host.fittingSize, appearance: appearance, to: url)
  }

  static func render(
    _ session: VaultSession, size: CGSize, appearance: NSAppearance.Name, to url: URL,
    interact: @MainActor (NSWindow) -> Void = { _ in }
  ) {
    render(NSHostingView(rootView: ContentView().environment(session)), size: size, appearance: appearance, to: url, interact: interact)
  }

  static func render(
    _ contentView: NSView, size: CGSize, appearance: NSAppearance.Name, to url: URL,
    interact: @MainActor (NSWindow) -> Void = { _ in }
  ) {
    let window = OffscreenWindow(
      contentRect: NSRect(origin: OffscreenWindow.origin, size: size),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: appearance)
    window.contentView = contentView
    window.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    interact(window)
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    defer { window.orderOut(nil) }

    // Liquid Glass は画面合成の段階で描かれるので、ウィンドウサーバから自分のウィンドウを撮る
    if let image = captureWindow(window.windowNumber) {
      try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
      return
    }
    let view = window.contentView!.superview ?? window.contentView!
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
  }

  /// 撮影用のウィンドウ。どの画面からも外れた場所に置き、使っている人の作業の前に出てこないようにする。
  /// 自分のウィンドウはウィンドウサーバから撮るので、画面の外にあっても描ける
  final class OffscreenWindow: NSWindow {
    static let origin = CGPoint(x: -30000, y: -30000)
    private var pretendsZoomed = false

    /// ふつうは画面の中へ引き戻されるので、置いた場所のままにする
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    /// 最大化は画面の中へ動かしてしまうので、画面いっぱいの大きさにするだけで、場所は画面の外のままにする
    override func zoom(_ sender: Any?) {
      pretendsZoomed = true
      let size = (NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 860)).size
      setFrame(NSRect(origin: .zero, size: size), display: true)
    }

    override var isZoomed: Bool { pretendsZoomed || super.isZoomed }

    /// 大きさを変えるときに画面の中へ動かされても（ContentView の大きさ合わせや SwiftUI など）、場所は画面の外のままにする
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
      super.setFrame(NSRect(origin: Self.origin, size: frameRect.size), display: flag)
    }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool) {
      super.setFrame(NSRect(origin: Self.origin, size: frameRect.size), display: displayFlag, animate: false)
    }

    override func setFrameOrigin(_ point: NSPoint) { super.setFrameOrigin(Self.origin) }
    override func setFrameTopLeftPoint(_ point: NSPoint) { super.setFrameOrigin(Self.origin) }
    override func center() {}

    /// クリックを試すときだけ、キーウィンドウのふりをする。
    /// 本当にキーにするにはアプリを前に出す必要があり、使っている人の作業の邪魔になる。キーでないと最初のクリックは捨てられる
    var pretendsKey = false
    override var isKeyWindow: Bool { pretendsKey || super.isKeyWindow }
  }

  static func findView<T: NSView>(_ type: T.Type, in view: NSView?) -> T? {
    guard let view else { return nil }
    if let found = view as? T { return found }
    for subview in view.subviews {
      if let found = findView(type, in: subview) { return found }
    }
    return nil
  }

  /// CGWindowListCreateImage は新しい SDK では使えない扱いなので、実行時に探して呼ぶ
  static func captureWindow(_ number: Int) -> CGImage? {
    typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
    let capture = unsafeBitCast(symbol, to: Capture.self)
    // kCGWindowListOptionIncludingWindow = 8, kCGWindowImageBoundsIgnoreFraming = 1, kCGWindowImageBestResolution = 8
    return capture(.null, 8, UInt32(number), 1 | 8)?.takeRetainedValue()
  }
}
#endif
