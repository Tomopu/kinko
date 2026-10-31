import CryptoKit
import Foundation
import KinkoCore
import LocalAuthentication

/// この Mac の Secure Enclave の鍵を、金庫ごとにファイルとして置く場所（~/Library/Application Support/Kinko/Keys）。
///
/// 置くのは Secure Enclave が包んだ鍵で、この Mac の Secure Enclave の中でしか使えない（秘密鍵そのものは外に出ない）。
/// キーチェーンを使わないのは、キーチェーンに Secure Enclave の鍵を置くには Apple Developer Program の署名が要るため。
/// バックアップからは外す。別の Mac に戻しても使えないうえ、消したはずの鍵がバックアップに残ると、
/// 「間違え続けたら鍵を消す」が効かなくなる
struct DeviceKeyStore: Sendable {
  let directory: URL

  static let standard = DeviceKeyStore(
    directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appending(path: "Kinko/Keys", directoryHint: .isDirectory))

  static var isSecureEnclaveAvailable: Bool { SecureEnclave.isAvailable }

  /// Touch ID が使える（センサーがあり、指紋が登録されている）
  static var isTouchIDAvailable: Bool {
    SecureEnclave.isAvailable && LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
  }

  // MARK: - この Mac 専用の金庫の鍵

  /// 新しい鍵を Secure Enclave の中に作る。指紋なしで使える（パスワードと組み合わせて使うので）。
  /// 金庫の印は金庫を作ってから決まるので、保存は save で別に行う
  func newDeviceKey() throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
    try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: try accessControl([.privateKeyUsage]))
  }

  func save(_ key: SecureEnclave.P256.KeyAgreement.PrivateKey, for vault: String) throws {
    try write(key.dataRepresentation, to: url(vault, "devicekey"))
  }

  func deviceKey(for vault: String) -> SecureEnclave.P256.KeyAgreement.PrivateKey? {
    guard let data = try? Data(contentsOf: url(vault, "devicekey")) else { return nil }
    return try? SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: data)
  }

  // MARK: - Touch ID

  private struct TouchIDRecord: Codable {
    /// Secure Enclave が包んだ、指紋が要る鍵
    var key: Data
    var token: QuickUnlockToken
  }

  /// Touch ID で開けるようにする。指紋が要る鍵を Secure Enclave の中に作り、データ鍵をその鍵で包んで置く。
  /// 包むのは公開鍵だけでできるので、ここでは指紋を求めない
  func enableTouchID(for vault: UnlockedVault) throws {
    let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(
      accessControl: try accessControl([.privateKeyUsage, .biometryCurrentSet]))
    let record = TouchIDRecord(key: key.dataRepresentation, token: try vault.quickUnlockToken(using: key))
    try write(try JSONEncoder().encode(record), to: url(vault.identifier, "touchid"))
  }

  func hasTouchID(for vault: String) -> Bool {
    FileManager.default.fileExists(atPath: url(vault, "touchid").path)
  }

  /// Touch ID で開く。鍵を使うときに macOS が指紋を求める（終わるまで戻らないので、メインスレッドで呼ばない）。
  /// 指紋を登録し直すと鍵が使えなくなる（biometryCurrentSet）ので、そのときは記録を消してパスワードに戻す
  func openWithTouchID(_ file: Data, vault: String, reason: String) throws -> (vault: UnlockedVault, plaintext: Data) {
    let record = try JSONDecoder().decode(TouchIDRecord.self, from: Data(contentsOf: url(vault, "touchid")))
    let context = LAContext()
    context.localizedReason = reason
    let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: record.key, authenticationContext: context)
    return try UnlockedVault.open(file, token: record.token, tokenKey: key)
  }

  func removeTouchID(for vault: String) {
    try? FileManager.default.removeItem(at: url(vault, "touchid"))
  }

  /// 金庫に関わる鍵をすべて消す。この Mac 専用の金庫なら、これでどのコピーもパスワードでは開けなくなる
  func removeAll(for vault: String) {
    try? FileManager.default.removeItem(at: url(vault, "devicekey"))
    removeTouchID(for: vault)
  }

  // MARK: - 内部

  private func url(_ vault: String, _ kind: String) -> URL {
    directory.appending(path: "\(vault).\(kind)")
  }

  private func write(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var excluded = URLResourceValues()
    excluded.isExcludedFromBackup = true
    var folder = directory
    try folder.setResourceValues(excluded)
    try data.write(to: url, options: .atomic)
    var file = url
    try file.setResourceValues(excluded)
  }

  private func accessControl(_ flags: SecAccessControlCreateFlags) throws -> SecAccessControl {
    var error: Unmanaged<CFError>?
    guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, flags, &error) else {
      throw error!.takeRetainedValue() as Error
    }
    return access
  }
}
