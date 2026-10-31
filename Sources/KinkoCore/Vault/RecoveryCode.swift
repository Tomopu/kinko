import Clibsodium
import CryptoKit
import Foundation

/// 復旧コード。この Mac 専用の金庫を、Mac を失くしたり初期化したりしたあとに開き直すための、紙に控える秘密。
///
/// 120 ビットの乱数を、読み間違えにくい Crockford の Base32（0〜9 と、I・L・O・U を除く英大文字）で
/// 4 文字ずつ 6 組にして見せる（例：7K3Q-...）。十分に長い乱数なので、パスワードと違って総当たりの心配がなく、
/// 重い Argon2id を通さずに HKDF で鍵にする
public struct RecoveryCode: Sendable, Equatable, CustomStringConvertible {
  static let byteCount = 15
  private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
  private static let characterCount = byteCount * 8 / 5

  let bytes: Data

  init(bytes: Data) {
    precondition(bytes.count == Self.byteCount)
    self.bytes = bytes
  }

  /// 新しい復旧コード
  public static func random() -> RecoveryCode {
    var bytes = Data(count: byteCount)
    bytes.withUnsafeMutableBytes { randombytes_buf($0.baseAddress!, $0.count) }
    return RecoveryCode(bytes: bytes)
  }

  /// 入力された復旧コードを読む。区切りの「-」や空白、小文字は気にしない。
  /// 見間違えやすい O は 0、I と L は 1 として読む（Crockford の決まり）。文字数が合わなければ nil
  public init?(_ text: String) {
    var value: [UInt8] = []
    for character in text.uppercased() {
      if character == "-" || character.isWhitespace { continue }
      let normalized: Character =
        switch character {
        case "O": "0"
        case "I", "L": "1"
        default: character
        }
      guard let index = Self.alphabet.firstIndex(of: normalized) else { return nil }
      value.append(UInt8(index))
    }
    guard value.count == Self.characterCount else { return nil }
    // 5 ビットずつ並べて 8 ビットずつに切り直す
    var bytes = Data()
    var buffer = 0
    var bits = 0
    for digit in value {
      buffer = buffer << 5 | Int(digit)
      bits += 5
      if bits >= 8 {
        bits -= 8
        bytes.append(UInt8(truncatingIfNeeded: buffer >> bits))
      }
    }
    self.init(bytes: bytes)
  }

  public var description: String {
    var characters: [Character] = []
    var buffer = 0
    var bits = 0
    for byte in bytes {
      buffer = buffer << 8 | Int(byte)
      bits += 8
      while bits >= 5 {
        bits -= 5
        characters.append(Self.alphabet[(buffer >> bits) & 31])
      }
    }
    return stride(from: 0, to: characters.count, by: 4)
      .map { String(characters[$0..<min($0 + 4, characters.count)]) }
      .joined(separator: "-")
  }

  /// データ鍵を包むための鍵。salt は金庫ごとに違うので、同じ復旧コードでも金庫ごとに別の鍵になる
  func wrappingKey(salt: Data) -> SymmetricKey {
    HKDF<SHA256>.deriveKey(
      inputKeyMaterial: SymmetricKey(data: bytes), salt: salt, info: Data("Kinko v2 recovery".utf8), outputByteCount: 32)
  }
}
