import AppKit
import SwiftUI

/// 機密向けのプレーンテキストエディタ（NSTextView）。
/// SwiftUI の TextEditor と違い、文字の内側の余白を指定できるので、エディタをウィンドウの端まで広げたまま読みやすくできる。
/// また、スペルチェックや自動補完・自動置換をまとめて切り、入力した内容がそうした機能に渡らないようにする
struct PlainTextEditor: NSViewRepresentable {
  @Binding var text: String

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSTextView.scrollableTextView()
    scrollView.drawsBackground = false
    let textView = scrollView.documentView as! NSTextView
    textView.delegate = context.coordinator
    textView.configureForSecrets()
    textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    textView.string = text
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.text = $text
    let textView = scrollView.documentView as! NSTextView
    // 入力中に毎回書き戻すとカーソルや変換中の文字が乱れるので、外から変わったときだけ入れ替える
    if textView.string != text {
      textView.string = text
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text)
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var text: Binding<String>

    init(text: Binding<String>) {
      self.text = text
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      text.wrappedValue = textView.string
    }
  }
}

extension NSTextView {
  /// 機密を書くエディタ共通の設定。スペルチェックや自動補完・自動置換・リンク検出をすべて切る
  func configureForSecrets() {
    drawsBackground = false
    isRichText = false
    importsGraphics = false
    allowsUndo = true
    textContainerInset = NSSize(width: 12, height: 10)
    isContinuousSpellCheckingEnabled = false
    isGrammarCheckingEnabled = false
    isAutomaticSpellingCorrectionEnabled = false
    isAutomaticTextCompletionEnabled = false
    isAutomaticTextReplacementEnabled = false
    isAutomaticQuoteSubstitutionEnabled = false
    isAutomaticDashSubstitutionEnabled = false
    isAutomaticLinkDetectionEnabled = false
    isAutomaticDataDetectionEnabled = false
  }
}
