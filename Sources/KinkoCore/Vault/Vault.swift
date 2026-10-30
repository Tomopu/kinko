import Clibsodium
import CryptoKit
import Foundation

public enum VaultError: Error, Equatable, LocalizedError {
  case emptyPassword
  case notAVault
  case unsupportedVersion(UInt8)
  case unsupportedKDF(UInt8)
  case unacceptableParameters
  case truncated
  /// パスワードの間違いと改ざんは、わざと区別しない（区別できると攻撃者に手がかりを与える）
  case authenticationFailed
  case kdfFailed

  public var errorDescription: String? {
    switch self {
    case .emptyPassword: "パスワードが空です。"
    case .notAVault: "Kinko のファイルではありません。"
    case .unsupportedVersion(let v): "対応していない形式のバージョンです（\(v)）。"
    case .unsupportedKDF(let k): "対応していない鍵導出方式です（\(k)）。"
    case .unacceptableParameters: "ファイルの鍵導出パラメータが許容範囲外です。"
    case .truncated: "ファイルが途中で切れています。"
    case .authenticationFailed: "パスワードが違うか、ファイルが改ざんされています。"
    case .kdfFailed: "鍵の導出に失敗しました。"
    }
  }
}

/// 解錠済みの金庫。
///
/// 鍵は 2 段になっている：
///   パスワード →(Argon2id)→ 鍵暗号化鍵 →(AES-GCM で包む)→ データ鍵 →(AES-GCM)→ 本文
/// 本文はランダムなデータ鍵で暗号化し、データ鍵だけをパスワード由来の鍵で包んでヘッダに入れる。
/// こうしておくと、データ鍵を消せば本文は二度と読めなくなる。
/// 解錠後はデータ鍵をメモリに持つので、保存のたびに重い Argon2id をやり直さずに済む。
public struct UnlockedVault: Sendable {
  let envelope: KeyEnvelope
  let dataKey: SymmetricKey

  /// 新しい金庫を作る。データ鍵と salt はここで乱数から作る
  public static func create(password: String, parameters: KDFParameters = .standard) throws -> UnlockedVault {
    var salt = Data(count: KeyDerivation.saltLength)
    salt.withUnsafeMutableBytes { randombytes_buf($0.baseAddress!, $0.count) }
    let keyEncryptionKey = try KeyDerivation.deriveKey(password: password, salt: salt, parameters: parameters)

    let dataKey = SymmetricKey(size: .bits256)
    var rawDataKey = dataKey.withUnsafeBytes { Array($0) }
    defer { sodium_memzero(&rawDataKey, rawDataKey.count) }

    let prefix = KeyEnvelope.encodePrefix(parameters: parameters, salt: salt)
    let wrapped = try AES.GCM.seal(rawDataKey, using: keyEncryptionKey, authenticating: prefix)
    let envelope = KeyEnvelope(
      parameters: parameters,
      salt: salt,
      wrapNonce: Data(wrapped.nonce),
      wrappedKey: wrapped.ciphertext + wrapped.tag
    )
    return UnlockedVault(envelope: envelope, dataKey: dataKey)
  }

  /// ファイルを開き、金庫と本文の平文を返す
  public static func open(_ file: Data, password: String) throws -> (vault: UnlockedVault, plaintext: Data) {
    let parsed = try VaultFile.parse(file)
    let envelope = parsed.envelope
    let keyEncryptionKey = try KeyDerivation.deriveKey(
      password: password, salt: envelope.salt, parameters: envelope.parameters)

    var rawDataKey = try authenticatedOpen(
      envelope.wrappedKey, nonce: envelope.wrapNonce, key: keyEncryptionKey, aad: envelope.encodedPrefix)
    defer { rawDataKey.resetBytes(in: rawDataKey.startIndex..<rawDataKey.endIndex) }
    let dataKey = SymmetricKey(data: rawDataKey)

    let plaintext = try authenticatedOpen(
      parsed.body, nonce: parsed.bodyNonce, key: dataKey, aad: parsed.header)
    return (UnlockedVault(envelope: envelope, dataKey: dataKey), plaintext)
  }

  /// パスワードが正しいか確かめる。ヘッダの salt とパラメータで鍵を作り直し、データ鍵を取り出せるかを見る
  public func verifies(password: String) -> Bool {
    guard
      let keyEncryptionKey = try? KeyDerivation.deriveKey(
        password: password, salt: envelope.salt, parameters: envelope.parameters),
      var rawDataKey = try? Self.authenticatedOpen(
        envelope.wrappedKey, nonce: envelope.wrapNonce, key: keyEncryptionKey, aad: envelope.encodedPrefix)
    else { return false }
    rawDataKey.resetBytes(in: rawDataKey.startIndex..<rawDataKey.endIndex)
    return true
  }

  /// 新しいパスワードの金庫に作り替える。
  /// データ鍵を包み直すだけでなく、データ鍵そのものも新しくする。古いパスワードが漏れていた場合、
  /// 攻撃者が以前のファイルのコピーから古いデータ鍵を取り出せるので、同じデータ鍵のままだと新しいファイルまで読まれてしまう
  public func changingPassword(to newPassword: String, parameters: KDFParameters = .standard) throws -> UnlockedVault {
    try UnlockedVault.create(password: newPassword, parameters: parameters)
  }

  /// 本文を暗号化してファイルの中身を作る。nonce は毎回新しい乱数にする
  public func seal(_ plaintext: Data) throws -> Data {
    let nonce = AES.GCM.Nonce()
    let header = envelope.encoded + Data(nonce)
    let box = try AES.GCM.seal(plaintext, using: dataKey, nonce: nonce, authenticating: header)
    return header + box.ciphertext + box.tag
  }

  private static func authenticatedOpen(_ sealed: Data, nonce: Data, key: SymmetricKey, aad: Data) throws -> Data {
    do {
      let box = try AES.GCM.SealedBox(
        nonce: AES.GCM.Nonce(data: nonce),
        ciphertext: sealed.dropLast(VaultFile.tagLength),
        tag: sealed.suffix(VaultFile.tagLength))
      return try AES.GCM.open(box, using: key, authenticating: aad)
    } catch {
      throw VaultError.authenticationFailed
    }
  }
}
