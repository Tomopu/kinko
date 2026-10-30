import CryptoKit
import Foundation
import Testing

@testable import KinkoCore

private let fast = KDFParameters(memoryKiB: 8, iterations: 1)

@Test func verifiesOnlyTheCurrentPassword() throws {
  let vault = try UnlockedVault.create(password: "old passphrase", parameters: fast)
  #expect(vault.verifies(password: "old passphrase"))
  #expect(!vault.verifies(password: "Old passphrase"))
  #expect(!vault.verifies(password: ""))
}

@Test func changedVaultOpensOnlyWithNewPassword() throws {
  let old = try UnlockedVault.create(password: "古いパスワード", parameters: fast)
  let changed = try old.changingPassword(to: "new passphrase 2026", parameters: fast)
  let file = try changed.seal(Data("中身はそのまま".utf8))

  #expect(throws: VaultError.authenticationFailed) { try UnlockedVault.open(file, password: "古いパスワード") }
  let reopened = try UnlockedVault.open(file, password: "new passphrase 2026")
  #expect(String(decoding: reopened.plaintext, as: UTF8.self) == "中身はそのまま")
  #expect(reopened.vault.verifies(password: "new passphrase 2026"))
}

/// 古いパスワードが漏れていても新しいファイルを読まれないよう、データ鍵と salt も新しくなっている
@Test func changeRotatesDataKeyAndSalt() throws {
  let old = try UnlockedVault.create(password: "old passphrase", parameters: fast)
  let changed = try old.changingPassword(to: "new passphrase", parameters: fast)
  let oldKey = old.dataKey.withUnsafeBytes { Data($0) }
  let newKey = changed.dataKey.withUnsafeBytes { Data($0) }
  #expect(oldKey != newKey)
  #expect(old.envelope.salt != changed.envelope.salt)

  // 古いデータ鍵では、新しい金庫で暗号化した本文を開けない
  let file = try changed.seal(Data("秘密".utf8))
  let body = file.dropFirst(VaultFile.headerLength)
  let box = try AES.GCM.SealedBox(
    nonce: AES.GCM.Nonce(data: file.subdata(in: (VaultFile.headerLength - VaultFile.nonceLength)..<VaultFile.headerLength)),
    ciphertext: body.dropLast(VaultFile.tagLength), tag: body.suffix(VaultFile.tagLength))
  #expect(throws: (any Error).self) {
    try AES.GCM.open(box, using: old.dataKey, authenticating: file.prefix(VaultFile.headerLength))
  }
}
