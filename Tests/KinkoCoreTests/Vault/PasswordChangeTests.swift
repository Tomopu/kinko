import CryptoKit
import Foundation
import Testing

@testable import KinkoCore

@Suite("パスワードの変更")
struct PasswordChangeTests {
  /// テストでは Argon2id を最小の重さにして速く回す
  private let fast = KDFParameters(memoryKiB: 8, iterations: 1)

  @Test("今のパスワードと完全に同じときだけ一致とみなす")
  func verifiesOnlyTheCurrentPassword() throws {
    // Given
    let vault = try UnlockedVault.create(password: "old passphrase", parameters: fast)

    // When / Then: 大文字小文字の違いや空は通さない
    #expect(vault.verifies(password: "old passphrase"))
    #expect(!vault.verifies(password: "Old passphrase"))
    #expect(!vault.verifies(password: ""))
  }

  @Test("変更後に保存したファイルは、新しいパスワードでだけ開ける")
  func changedVaultOpensOnlyWithNewPassword() throws {
    // Given
    let old = try UnlockedVault.create(password: "古いパスワード", parameters: fast)

    // When: パスワードを変えて保存する
    let changed = try old.changingPassword(to: "new passphrase 2026", parameters: fast)
    let file = try changed.seal(Data("中身はそのまま".utf8))

    // Then
    #expect(throws: VaultError.authenticationFailed) { try UnlockedVault.open(file, password: "古いパスワード") }
    let reopened = try UnlockedVault.open(file, password: "new passphrase 2026")
    #expect(String(decoding: reopened.plaintext, as: UTF8.self) == "中身はそのまま")
    #expect(reopened.vault.verifies(password: "new passphrase 2026"))
  }

  /// 古いパスワードが漏れていても新しいファイルを読まれないよう、データ鍵と salt も新しくなっている
  @Test("変更するとデータ鍵と salt も作り直し、古いデータ鍵では新しいファイルを開けない")
  func changeRotatesDataKeyAndSalt() throws {
    // Given
    let old = try UnlockedVault.create(password: "old passphrase", parameters: fast)

    // When
    let changed = try old.changingPassword(to: "new passphrase", parameters: fast)
    let file = try changed.seal(Data("秘密".utf8))

    // Then: 鍵と salt が変わっている
    let oldKey = old.dataKey.withUnsafeBytes { Data($0) }
    let newKey = changed.dataKey.withUnsafeBytes { Data($0) }
    #expect(oldKey != newKey)
    #expect(old.salt != changed.salt)

    // Then: 古いデータ鍵では、新しい金庫で暗号化した本文を開けない
    let body = file.dropFirst(VaultFile.headerLength)
    let box = try AES.GCM.SealedBox(
      nonce: AES.GCM.Nonce(data: file.subdata(in: (VaultFile.headerLength - VaultFile.nonceLength)..<VaultFile.headerLength)),
      ciphertext: body.dropLast(VaultFile.tagLength), tag: body.suffix(VaultFile.tagLength))
    #expect(throws: (any Error).self) {
      try AES.GCM.open(box, using: old.dataKey, authenticating: file.prefix(VaultFile.headerLength))
    }
  }
}
