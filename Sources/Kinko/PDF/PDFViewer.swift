import PDFKit
import SwiftUI

/// 金庫の中の PDF を見る画面。見るだけで、書き換えない。下に今のページと拡大・縮小のボタン
struct PDFViewer: View {
  @State private var model: PDFViewerModel

  init(data: Data) {
    _model = State(initialValue: PDFViewerModel(data: data))
  }

  var body: some View {
    VStack(spacing: 0) {
      if let document = model.document, !model.isLocked {
        PDFKitView(model: model)
        Divider()
        bottomBar(document)
      } else if model.document != nil {
        PDFPasswordView(model: model)
      } else {
        ContentUnavailableView("PDF を表示できません", systemImage: "exclamationmark.triangle", description: Text("ファイルが壊れている可能性があります。"))
      }
    }
  }

  private func bottomBar(_ document: PDFDocument) -> some View {
    HStack(spacing: 4) {
      Text("\(model.pageIndex + 1) / \(document.pageCount) ページ")
        .monospacedDigit()
        .foregroundStyle(.secondary)
      Spacer()
      Button("縮小", systemImage: "minus.magnifyingglass") { model.zoom(by: 1 / 1.25) }
        .hoverLabel("縮小（⌘−）")
        .keyboardShortcut("-")
      Button("幅に合わせる", systemImage: "arrow.left.and.right.square") { model.fitWidth() }
        .hoverLabel("幅に合わせる（⌘0）")
        .keyboardShortcut("0")
      Button("拡大", systemImage: "plus.magnifyingglass") { model.zoom(by: 1.25) }
        .hoverLabel("拡大（⌘＋）")
        .keyboardShortcut("+")
    }
    .labelStyle(.iconOnly)
    .buttonStyle(.borderless)
    .font(.callout)
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
  }
}

@MainActor
@Observable
final class PDFViewerModel {
  let document: PDFDocument?
  private(set) var pageIndex = 0
  /// パスワード付きの PDF で、まだ開いていない
  private(set) var isLocked: Bool
  /// パスワード付きの PDF で、パスワードが違ったとき
  var unlockFailed = false
  @ObservationIgnored weak var view: PDFView?

  init(data: Data) {
    document = PDFDocument(data: data)
    isLocked = document?.isLocked ?? false
  }

  func pageChanged() {
    guard let view, let page = view.currentPage, let document else { return }
    pageIndex = document.index(for: page)
  }

  func zoom(by factor: CGFloat) {
    guard let view else { return }
    view.autoScales = false
    view.scaleFactor = min(max(view.scaleFactor * factor, view.minScaleFactor), view.maxScaleFactor)
  }

  func fitWidth() {
    view?.autoScales = true
  }

  /// パスワード付きの PDF を開く（PDF そのもののパスワード。金庫のパスワードとは別）
  func unlock(_ password: String) {
    let ok = document?.unlock(withPassword: password) ?? false
    unlockFailed = !ok
    isLocked = !ok
  }
}

private struct PDFKitView: NSViewRepresentable {
  let model: PDFViewerModel

  func makeNSView(context: Context) -> PDFView {
    let view = PDFView()
    view.document = model.document
    view.displayMode = .singlePageContinuous
    view.displaysPageBreaks = true
    view.autoScales = true
    view.backgroundColor = .underPageBackgroundColor
    model.view = view
    context.coordinator.observation = NotificationCenter.default.addObserver(
      forName: .PDFViewPageChanged, object: view, queue: .main
    ) { _ in
      MainActor.assumeIsolated { model.pageChanged() }
    }
    return view
  }

  func updateNSView(_ view: PDFView, context: Context) {}

  func makeCoordinator() -> Coordinator { Coordinator() }

  final class Coordinator {
    var observation: (any NSObjectProtocol)?
    deinit {
      if let observation { NotificationCenter.default.removeObserver(observation) }
    }
  }
}

/// パスワード付きの PDF を開くための入力欄
private struct PDFPasswordView: View {
  let model: PDFViewerModel
  @State private var password = ""

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "lock.doc").font(.system(size: 36)).foregroundStyle(.secondary)
      Text("この PDF にはパスワードがかかっています").font(.headline)
      Text("PDF を作った人が付けたパスワードです（金庫のパスワードとは別です）。")
        .foregroundStyle(.secondary)
      SecureField("PDF のパスワード", text: $password)
        .textFieldStyle(.roundedBorder)
        .frame(width: 260)
        .onSubmit(submit)
      if model.unlockFailed {
        Text("パスワードが違います。").foregroundStyle(.red)
      }
      Button("開く", action: submit).keyboardShortcut(.defaultAction).disabled(password.isEmpty)
    }
    .padding(32)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func submit() {
    guard !password.isEmpty else { return }
    model.unlock(password)
    password = ""
  }
}
