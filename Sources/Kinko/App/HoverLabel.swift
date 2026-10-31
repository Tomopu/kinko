import AppKit
import SwiftUI

extension View {
  /// マウスを重ねると、少し待ってから名前を小さな札で出す。
  /// SwiftUI の .help は出るまでが遅く、置き場所（サイドバーの下や書式バー）によっては出ないので、自分で出す
  func hoverLabel(_ text: String) -> some View {
    modifier(HoverLabel(text: text))
  }
}

private struct HoverLabel: ViewModifier {
  let text: String
  @State private var pending: Task<Void, Never>?

  func body(content: Content) -> some View {
    content
      .onHover { inside in
        pending?.cancel()
        if inside {
          pending = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            HoverLabelPanel.shared.show(text)
          }
        } else {
          HoverLabelPanel.shared.hide(text)
        }
      }
      .onDisappear {
        pending?.cancel()
        HoverLabelPanel.shared.hide(text)
      }
  }
}

/// 札の見た目
struct HoverLabelView: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.callout)
      .frame(maxWidth: 320, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
      .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
      .padding(6)
  }
}

/// 札を出す小さなウィンドウ。ウィンドウなので、ほかの部品の下に隠れたり、端で切れたりしない
@MainActor
final class HoverLabelPanel {
  static let shared = HoverLabelPanel()

  private let panel: NSPanel
  private var shownText: String?
  private var monitor: Any?

  private init() {
    panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.ignoresMouseEvents = true
    panel.level = .popUpMenu
    panel.collectionBehavior = [.transient, .ignoresCycle]
  }

  /// マウスの少し下に出す。画面の下端に近ければ上に出す
  func show(_ text: String) {
    let hosting = NSHostingView(rootView: HoverLabelView(text: text))
    let size = hosting.fittingSize
    panel.contentView = hosting
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { $0.frame.contains(mouse) }?.visibleFrame ?? .zero
    var origin = NSPoint(x: mouse.x - 10, y: mouse.y - 22 - size.height)
    if origin.y < screen.minY { origin.y = mouse.y + 12 }
    origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
    panel.setFrame(NSRect(origin: origin, size: size), display: true)
    panel.orderFrontRegardless()
    shownText = text
    // 押したり打ったりしたら消す（ふつうのツールチップと同じ）
    if monitor == nil {
      monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { event in
        HoverLabelPanel.shared.hide()
        return event
      }
    }
  }

  /// text を渡したときは、その札が出ているときだけ消す（次の部品の札を、前の部品が消さないように）
  func hide(_ text: String? = nil) {
    guard text == nil || text == shownText else { return }
    panel.orderOut(nil)
    shownText = nil
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
  }
}
