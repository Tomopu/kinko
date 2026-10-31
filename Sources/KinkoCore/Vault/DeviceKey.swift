import CryptoKit
import Foundation

/// この Mac の中にあって、外へ出せない鍵（Secure Enclave の P-256 鍵）。
/// 秘密鍵そのものは取り出せず、相手の公開鍵との ECDH（共有の秘密を作る計算）だけを頼める。
/// テストでは、ふつうのソフトウェアの P-256 鍵で代わりをする
public protocol DeviceKey: Sendable {
  var publicKey: P256.KeyAgreement.PublicKey { get }
  func sharedSecretFromKeyAgreement(with publicKeyShare: P256.KeyAgreement.PublicKey) throws -> SharedSecret
}

extension SecureEnclave.P256.KeyAgreement.PrivateKey: DeviceKey {}
extension P256.KeyAgreement.PrivateKey: DeviceKey {}

/// データ鍵を、端末の鍵で包む（ECIES と同じ形）。
/// 使い捨ての鍵ペアを作り、その秘密鍵と端末の公開鍵で ECDH し、HKDF で包むための鍵にする。
/// 開くときは、端末の鍵と使い捨ての公開鍵で ECDH すれば同じ共有の秘密になる
enum DeviceWrap {
  /// 使い捨ての鍵ペアと共有の秘密を作る。公開鍵はファイルに残す
  static func agree(with deviceKey: some DeviceKey) throws -> (ephemeralPublicKey: Data, shared: SharedSecret) {
    let ephemeral = P256.KeyAgreement.PrivateKey()
    let shared = try ephemeral.sharedSecretFromKeyAgreement(with: deviceKey.publicKey)
    return (ephemeral.publicKey.x963Representation, shared)
  }

  /// 端末の鍵で、ファイルにある使い捨ての公開鍵との共有の秘密を作る
  static func agree(with deviceKey: some DeviceKey, ephemeralPublicKey: Data) throws -> SharedSecret {
    let publicKey: P256.KeyAgreement.PublicKey
    do {
      publicKey = try P256.KeyAgreement.PublicKey(x963Representation: ephemeralPublicKey)
    } catch {
      throw VaultError.authenticationFailed
    }
    return try deviceKey.sharedSecretFromKeyAgreement(with: publicKey)
  }

  static func bytes(of shared: SharedSecret) -> Data {
    shared.withUnsafeBytes { Data($0) }
  }
}
