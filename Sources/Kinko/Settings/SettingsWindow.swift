import AppKit
import SwiftUI

/// 設定のウィンドウ。SwiftUI の Settings にはコードから閉じる手段がないので、表示されたときにウィンドウを覚えておく
@MainActor
enum SettingsWindow {
  private static weak var window: NSWindow?

  /// 開いていれば閉じる（設定を開いたまま新しいファイルを作るときなど）
  static func close() {
    guard let window, window.isVisible else { return }
    window.close()
  }

  /// 設定の画面の背景に置き、載っているウィンドウを覚える
  struct Tracker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { TrackingView() }
    func updateNSView(_ view: NSView, context: Context) {}
  }

  private final class TrackingView: NSView {
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if let window { SettingsWindow.window = window }
    }
  }
}
