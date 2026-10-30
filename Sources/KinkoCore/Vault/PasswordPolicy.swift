import Foundation

/// 新しい金庫のパスワードの規則。
///
/// 使えるのは半角の英数字・記号・空白（ASCII の 0x20〜0x7E）だけにする。日本語を入れさせない理由：
/// - 日本語入力（IME）は別のプロセスで、打った文字を変換候補として画面に出し、学習データとしてディスクに残す。
///   パスワードを IME に通すと、隠しているはずの文字がそこから漏れる
/// - そのため macOS はパスワード欄で IME を止める。日本語を打つには表示状態にするしかなく、肩越しにも見える
/// - 同じ言葉でも、IME や設定によって全角・半角や「〜」「～」のような違う文字になり、別の Mac で開けなくなりうる
/// 強さは文字の種類ではなく、長さと選び方のランダムさで決まるので、日本語を禁じても弱くはならない
/// （「こんにちは」は辞書攻撃ですぐ見つかるが、ランダムに選んだ単語を 5 つつなげたローマ字は十分に強い）
public enum PasswordPolicy {
  public static let minimumLength = 8

  public enum Violation: Error, Equatable, LocalizedError {
    case tooShort
    case unsupportedCharacters

    public var errorDescription: String? {
      switch self {
      case .tooShort:
        "パスワードは \(PasswordPolicy.minimumLength) 文字以上にしてください。"
      case .unsupportedCharacters:
        "パスワードには半角の英数字・記号・空白だけが使えます。日本語や全角の文字は使えません。"
      }
    }
  }

  public static func validate(_ password: String) throws(Violation) {
    guard password.unicodeScalars.allSatisfy({ (0x20...0x7E).contains($0.value) }) else {
      throw .unsupportedCharacters
    }
    guard password.unicodeScalars.count >= minimumLength else { throw .tooShort }
  }
}
