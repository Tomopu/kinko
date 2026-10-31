import AppKit
import SwiftUI

/// 右端の目のボタンで表示・非表示を切り替えられるパスワード欄。
/// 隠している間は SecureField なので、macOS が Secure Event Input を有効にし、他のアプリからキー入力を盗み見られにくくなる。
/// 表示中は普通の TextField になり、この守りが外れる。
/// どちらの状態でも日本語入力（IME）は使わせない。IME は打った文字を変換候補として表示し、学習データとして保存するので、
/// パスワードを通すとそこから漏れる（理由の詳細は PasswordPolicy）
struct PasswordField: View {
  let title: String
  @Binding var text: String

  @State private var isRevealed = false
  @FocusState private var isFocused: Bool

  var body: some View {
    HStack(spacing: 6) {
      Group {
        if isRevealed {
          TextField(title, text: $text)
        } else {
          SecureField(title, text: $text)
        }
      }
      .textFieldStyle(.plain)
      .autocorrectionDisabled()
      .focused($isFocused)
      .background(RomanInputOnly(isFocused: isFocused, isRevealed: isRevealed))
      eyeButton
    }
    .font(.system(size: 14))
    .padding(.leading, 10)
    .padding(.trailing, 6)
    .padding(.vertical, 8)
    .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .textBackgroundColor)))
    .overlay(
      RoundedRectangle(cornerRadius: 7)
        .strokeBorder(isFocused ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isFocused ? 2 : 1)
    )
  }

  private var eyeButton: some View {
    Button {
      isRevealed.toggle()
      isFocused = true
    } label: {
      Image(systemName: isRevealed ? "eye.slash" : "eye")
        .frame(width: 20, height: 20)
        .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .foregroundStyle(.secondary)
    .hoverLabel(isRevealed ? "パスワードを隠す" : "パスワードを表示")
    .accessibilityLabel(isRevealed ? "パスワードを隠す" : "パスワードを表示")
  }
}

/// 入力欄が選ばれている間、その入力欄の編集部品（ウィンドウ共通のフィールドエディタ）を英字入力だけに制限する。
/// macOS は許可されていない入力ソースが選ばれていると、英字の入力ソースへ自動で切り替える
private struct RomanInputOnly: NSViewRepresentable {
  let isFocused: Bool
  /// 表示・非表示を切り替えると入力欄が作り直されるので、そのたびにかけ直す
  let isRevealed: Bool

  func makeNSView(context: Context) -> NSView { NSView() }

  func updateNSView(_ view: NSView, context: Context) {
    guard isFocused else { return }
    let coordinator = context.coordinator
    DispatchQueue.main.async {
      guard let editor = view.window?.firstResponder as? NSTextView, editor.isFieldEditor else { return }
      editor.inputContext?.allowedInputSourceLocales = [NSAllRomanInputSourcesLocaleIdentifier]
      coordinator.editor = editor
    }
  }

  /// フィールドエディタはウィンドウ内の入力欄で共有されるので、パスワードの画面を離れるときに制限を外す。
  /// 2 つのパスワード欄の間でフォーカスが移るときは外さない（外す処理とかける処理の順番が入れ替わると、制限が消えるため）
  static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
    coordinator.editor?.inputContext?.allowedInputSourceLocales = nil
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  final class Coordinator {
    weak var editor: NSTextView?
  }
}
