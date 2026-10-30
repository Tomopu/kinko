import Clibsodium
import CryptoKit
import Foundation

/// Argon2id のパラメータ。ファイルのヘッダに保存し、開くときに同じ値で鍵を作り直す
public struct KDFParameters: Sendable, Equatable {
  /// 使うメモリ量（KiB）
  public var memoryKiB: UInt32
  /// 繰り返し回数
  public var iterations: UInt32

  public init(memoryKiB: UInt32, iterations: UInt32) {
    self.memoryKiB = memoryKiB
    self.iterations = iterations
  }

  /// 通常の設定：256 MiB・3 回（libsodium の MODERATE と同じ）
  public static let standard = KDFParameters(memoryKiB: 256 * 1024, iterations: 3)

  /// ファイルから読んだ値として受け入れる範囲。
  /// 上限がないと、細工したファイルで何十 GB ものメモリを要求され、開いただけでアプリが落ちる
  static let acceptedMemoryKiB: ClosedRange<UInt32> = 8...(1024 * 1024)
  static let acceptedIterations: ClosedRange<UInt32> = 1...16

  var isAccepted: Bool {
    Self.acceptedMemoryKiB.contains(memoryKiB) && Self.acceptedIterations.contains(iterations)
  }
}

enum KeyDerivation {
  static let saltLength = 16
  static let keyLength = 32

  private static let sodiumReady: Bool = sodium_init() >= 0

  /// パスワードから 256 ビットの鍵を作る（Argon2id v1.3）
  static func deriveKey(password: String, salt: Data, parameters: KDFParameters) throws -> SymmetricKey {
    guard sodiumReady else { throw VaultError.kdfFailed }
    guard !password.isEmpty else { throw VaultError.emptyPassword }
    guard salt.count == saltLength, parameters.isAccepted else { throw VaultError.unacceptableParameters }

    // 見た目が同じ文字でも Unicode の表し方が複数ある（例：「が」と「か＋濁点」）ので、NFC にそろえる
    var passwordBytes = Array(password.precomposedStringWithCanonicalMapping.utf8)
    var output = [UInt8](repeating: 0, count: keyLength)
    // 使い終わった秘密はゼロで上書きする。String や SymmetricKey の内部コピーまでは消せないので、ベストエフォート
    defer {
      sodium_memzero(&passwordBytes, passwordBytes.count)
      sodium_memzero(&output, output.count)
    }

    let result = passwordBytes.withUnsafeBytes { password in
      salt.withUnsafeBytes { salt in
        crypto_pwhash(
          &output, UInt64(keyLength),
          password.baseAddress!.assumingMemoryBound(to: CChar.self), UInt64(password.count),
          salt.baseAddress!.assumingMemoryBound(to: UInt8.self),
          UInt64(parameters.iterations),
          Int(parameters.memoryKiB) * 1024,
          crypto_pwhash_alg_argon2id13()
        )
      }
    }
    guard result == 0 else { throw VaultError.kdfFailed }
    return SymmetricKey(data: output)
  }
}
