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
  /// この Mac 専用の金庫を、この Mac の鍵なしで開こうとした（ほかの Mac か、鍵が消えた）
  case deviceKeyRequired
  /// 復旧コードは、この Mac 専用の金庫にしかない
  case notDeviceBound
  case recoveryFailed

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
    case .deviceKeyRequired: "この金庫はこの Mac 専用ですが、この Mac の鍵が見つかりません。復旧コードで開いてください。"
    case .notDeviceBound: "この金庫には復旧コードがありません（パスワードだけで開く金庫です）。"
    case .recoveryFailed: "復旧コードが違うか、ファイルが改ざんされています。"
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
///
/// この Mac 専用の金庫（形式バージョン 2）では、鍵暗号化鍵をパスワードとこの Mac の鍵（Secure Enclave）の両方から作る：
///   HKDF(Argon2id(パスワード) ‖ ECDH(Mac の鍵, 使い捨ての公開鍵)) → 鍵暗号化鍵
/// ファイルをほかの Mac へコピーしても、この Mac の鍵がないので、何回パスワードを試しても開けない。
/// Mac を失くしたときのために、同じデータ鍵を復旧コードから作った鍵でも包んでおく
public struct UnlockedVault: Sendable {
  let envelope: VaultEnvelope
  let dataKey: SymmetricKey

  public enum Protection: Sendable, Equatable {
    /// パスワードだけで開く（どの Mac でも開ける）
    case password
    /// パスワードとこの Mac の鍵で開く（復旧コードでも開ける）
    case deviceBound
  }

  public var protection: Protection {
    if case .deviceBound = envelope { .deviceBound } else { .password }
  }

  var salt: Data { envelope.salt }

  // MARK: - 作る

  /// パスワードだけで開く新しい金庫を作る。データ鍵と salt はここで乱数から作る
  public static func create(password: String, parameters: KDFParameters = .standard) throws -> UnlockedVault {
    let salt = randomSalt()
    let keyEncryptionKey = try KeyDerivation.deriveKey(password: password, salt: salt, parameters: parameters)
    let dataKey = SymmetricKey(size: .bits256)
    let prefix = KeyEnvelope.encodePrefix(parameters: parameters, salt: salt)
    let wrapped = try wrap(dataKey, with: keyEncryptionKey, aad: prefix)
    let envelope = KeyEnvelope(parameters: parameters, salt: salt, wrapNonce: wrapped.nonce, wrappedKey: wrapped.sealed)
    return UnlockedVault(envelope: .password(envelope), dataKey: dataKey)
  }

  /// この Mac 専用の新しい金庫を作る。復旧コードもここで作るので、利用者に控えてもらう
  public static func create(
    password: String, deviceKey: some DeviceKey, parameters: KDFParameters = .standard
  ) throws -> (vault: UnlockedVault, recoveryCode: RecoveryCode) {
    let salt = randomSalt()
    let passwordKey = try KeyDerivation.deriveKey(password: password, salt: salt, parameters: parameters)
    let (ephemeralPublicKey, shared) = try DeviceWrap.agree(with: deviceKey)
    let prefix = DeviceBoundEnvelope.encodePrefix(parameters: parameters, salt: salt, ephemeralPublicKey: ephemeralPublicKey)
    let dataKey = SymmetricKey(size: .bits256)
    let recoveryCode = RecoveryCode.random()
    let envelope = DeviceBoundEnvelope(
      parameters: parameters, salt: salt, ephemeralPublicKey: ephemeralPublicKey,
      passwordSlot: try wrap(dataKey, with: deviceBoundKey(passwordKey, shared, salt: salt), aad: prefix),
      recoverySlot: try wrap(dataKey, with: recoveryCode.wrappingKey(salt: salt), aad: prefix))
    return (UnlockedVault(envelope: .deviceBound(envelope), dataKey: dataKey), recoveryCode)
  }

  // MARK: - 開く

  /// ファイルを開き、金庫と本文の平文を返す。この Mac 専用の金庫には deviceKey が要る
  public static func open(
    _ file: Data, password: String, deviceKey: (any DeviceKey)? = nil
  ) throws -> (vault: UnlockedVault, plaintext: Data) {
    let parsed = try VaultFile.parse(file)
    let dataKey = try unwrapDataKey(parsed.envelope, password: password, deviceKey: deviceKey)
    return try openBody(parsed, dataKey: dataKey)
  }

  /// 復旧コードで開く（この Mac 専用の金庫だけ）
  public static func open(_ file: Data, recoveryCode: RecoveryCode) throws -> (vault: UnlockedVault, plaintext: Data) {
    let parsed = try VaultFile.parse(file)
    guard case .deviceBound(let envelope) = parsed.envelope else { throw VaultError.notDeviceBound }
    let dataKey: SymmetricKey
    do {
      dataKey = try unwrap(
        envelope.recoverySlot, with: recoveryCode.wrappingKey(salt: envelope.salt), aad: envelope.encodedPrefix)
    } catch {
      throw VaultError.recoveryFailed
    }
    return try openBody(parsed, dataKey: dataKey)
  }

  /// Touch ID などで開く。token は、この金庫のデータ鍵を tokenKey で包んだもの（ファイルの外に置いてある）
  public static func open(
    _ file: Data, token: QuickUnlockToken, tokenKey: some DeviceKey
  ) throws -> (vault: UnlockedVault, plaintext: Data) {
    let parsed = try VaultFile.parse(file)
    let shared = try DeviceWrap.agree(with: tokenKey, ephemeralPublicKey: token.ephemeralPublicKey)
    let dataKey = try unwrap(
      WrappedKey(nonce: token.nonce, sealed: token.sealed), with: QuickUnlockToken.wrappingKey(shared, salt: parsed.envelope.salt),
      aad: QuickUnlockToken.aad(salt: parsed.envelope.salt))
    return try openBody(parsed, dataKey: dataKey)
  }

  /// 開く前のファイルが、パスワードだけで開くものか、この Mac 専用か
  public static func protection(ofFile file: Data) throws -> Protection {
    if case .deviceBound = try VaultFile.parse(file).envelope { .deviceBound } else { .password }
  }

  // MARK: - 見分ける印

  /// 金庫を見分ける印（ヘッダの salt を 16 進にしたもの）。保存し直しても変わらず、パスワードを変えると変わる。
  /// 秘密ではない（ファイルの先頭にそのまま書いてある）
  public var identifier: String { Self.identifier(ofSalt: salt) }

  /// 開く前のファイルから、金庫を見分ける印を読む
  public static func identifier(ofFile file: Data) throws -> String {
    identifier(ofSalt: try VaultFile.parse(file).envelope.salt)
  }

  private static func identifier(ofSalt salt: Data) -> String {
    salt.map { String(format: "%02x", $0) }.joined()
  }

  // MARK: - 開いたあと

  /// パスワードが正しいか確かめる。ヘッダの salt とパラメータで鍵を作り直し、データ鍵を取り出せるかを見る。
  /// この Mac 専用の金庫では、この Mac の鍵も要る
  public func verifies(password: String, deviceKey: (any DeviceKey)? = nil) -> Bool {
    (try? Self.unwrapDataKey(envelope, password: password, deviceKey: deviceKey)) != nil
  }

  /// 新しいパスワードの、パスワードだけで開く金庫に作り替える。
  /// データ鍵を包み直すだけでなく、データ鍵そのものも新しくする。古いパスワードが漏れていた場合、
  /// 攻撃者が以前のファイルのコピーから古いデータ鍵を取り出せるので、同じデータ鍵のままだと新しいファイルまで読まれてしまう
  public func changingPassword(to newPassword: String, parameters: KDFParameters = .standard) throws -> UnlockedVault {
    try UnlockedVault.create(password: newPassword, parameters: parameters)
  }

  /// 鍵を作り直す。deviceKey があればこの Mac 専用に、なければパスワードだけで開く金庫にする。
  /// パスワードの変更、この Mac 専用への切り替えと解除、復旧コードで開いたあとの作り直しに使う。
  /// データ鍵も salt も復旧コードも新しくなる（古いパスワードや古い復旧コードが漏れていても、新しいファイルは読めない）
  public func rekeyed(
    password: String, deviceKey: (any DeviceKey)?, parameters: KDFParameters = .standard
  ) throws -> (vault: UnlockedVault, recoveryCode: RecoveryCode?) {
    guard let deviceKey else { return (try UnlockedVault.create(password: password, parameters: parameters), nil) }
    return try UnlockedVault.create(password: password, deviceKey: deviceKey, parameters: parameters)
  }

  /// Touch ID などで開くための token を作る。データ鍵を tokenKey で包む
  public func quickUnlockToken(using tokenKey: some DeviceKey) throws -> QuickUnlockToken {
    let (ephemeralPublicKey, shared) = try DeviceWrap.agree(with: tokenKey)
    let wrapped = try Self.wrap(
      dataKey, with: QuickUnlockToken.wrappingKey(shared, salt: salt), aad: QuickUnlockToken.aad(salt: salt))
    return QuickUnlockToken(ephemeralPublicKey: ephemeralPublicKey, nonce: wrapped.nonce, sealed: wrapped.sealed)
  }

  /// 本文を暗号化してファイルの中身を作る。nonce は毎回新しい乱数にする
  public func seal(_ plaintext: Data) throws -> Data {
    let nonce = AES.GCM.Nonce()
    let header = envelope.encoded + Data(nonce)
    let box = try AES.GCM.seal(plaintext, using: dataKey, nonce: nonce, authenticating: header)
    return header + box.ciphertext + box.tag
  }

  // MARK: - 内部

  private static func randomSalt() -> Data {
    var salt = Data(count: KeyDerivation.saltLength)
    salt.withUnsafeMutableBytes { randombytes_buf($0.baseAddress!, $0.count) }
    return salt
  }

  /// パスワード由来の鍵と、この Mac の鍵との共有の秘密を合わせて、鍵暗号化鍵にする
  private static func deviceBoundKey(_ passwordKey: SymmetricKey, _ shared: SharedSecret, salt: Data) -> SymmetricKey {
    var material = passwordKey.withUnsafeBytes { Data($0) } + DeviceWrap.bytes(of: shared)
    defer { material.resetBytes(in: material.startIndex..<material.endIndex) }
    return HKDF<SHA256>.deriveKey(
      inputKeyMaterial: SymmetricKey(data: material), salt: salt, info: Data("Kinko v2 password+device".utf8), outputByteCount: 32)
  }

  private static func unwrapDataKey(
    _ envelope: VaultEnvelope, password: String, deviceKey: (any DeviceKey)?
  ) throws -> SymmetricKey {
    switch envelope {
    case .password(let envelope):
      let keyEncryptionKey = try KeyDerivation.deriveKey(password: password, salt: envelope.salt, parameters: envelope.parameters)
      return try unwrap(
        WrappedKey(nonce: envelope.wrapNonce, sealed: envelope.wrappedKey), with: keyEncryptionKey, aad: envelope.encodedPrefix)
    case .deviceBound(let envelope):
      guard let deviceKey else { throw VaultError.deviceKeyRequired }
      let shared = try DeviceWrap.agree(with: deviceKey, ephemeralPublicKey: envelope.ephemeralPublicKey)
      let passwordKey = try KeyDerivation.deriveKey(password: password, salt: envelope.salt, parameters: envelope.parameters)
      return try unwrap(
        envelope.passwordSlot, with: deviceBoundKey(passwordKey, shared, salt: envelope.salt), aad: envelope.encodedPrefix)
    }
  }

  private static func openBody(_ parsed: VaultFile.Parsed, dataKey: SymmetricKey) throws -> (vault: UnlockedVault, plaintext: Data) {
    let plaintext = try authenticatedOpen(parsed.body, nonce: parsed.bodyNonce, key: dataKey, aad: parsed.header)
    return (UnlockedVault(envelope: parsed.envelope, dataKey: dataKey), plaintext)
  }

  private static func wrap(_ dataKey: SymmetricKey, with key: SymmetricKey, aad: Data) throws -> WrappedKey {
    var raw = dataKey.withUnsafeBytes { Array($0) }
    defer { sodium_memzero(&raw, raw.count) }
    let sealed = try AES.GCM.seal(raw, using: key, authenticating: aad)
    return WrappedKey(nonce: Data(sealed.nonce), sealed: sealed.ciphertext + sealed.tag)
  }

  private static func unwrap(_ wrapped: WrappedKey, with key: SymmetricKey, aad: Data) throws -> SymmetricKey {
    var raw = try authenticatedOpen(wrapped.sealed, nonce: wrapped.nonce, key: key, aad: aad)
    defer { raw.resetBytes(in: raw.startIndex..<raw.endIndex) }
    return SymmetricKey(data: raw)
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

/// Touch ID などで開くための、データ鍵を端末の鍵で包んだもの。金庫のファイルには入れず、この Mac のアプリのフォルダに置く。
/// 包むのに使う鍵は Secure Enclave の中にあり、指紋で確かめないと使えない
public struct QuickUnlockToken: Codable, Sendable, Equatable {
  var ephemeralPublicKey: Data
  var nonce: Data
  var sealed: Data

  static func wrappingKey(_ shared: SharedSecret, salt: Data) -> SymmetricKey {
    shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data("Kinko quick unlock".utf8), outputByteCount: 32)
  }

  /// どの金庫の token かを AAD に入れておく（別の金庫の token を差し替えられても開かない）
  static func aad(salt: Data) -> Data { Data("Kinko quick unlock".utf8) + salt }
}
