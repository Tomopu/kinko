import CryptoKit
import Foundation
import Testing

@testable import KinkoCore

@Suite("この Mac 専用の金庫")
struct DeviceBoundVaultTests {
  /// テストでは Argon2id を最小の重さにして速く回す
  private let fast = KDFParameters(memoryKiB: 8, iterations: 1)
  /// この Mac の Secure Enclave の鍵の代わり
  private let thisMac = P256.KeyAgreement.PrivateKey()

  private func makeFile(body: String = "秘密のメモ") throws -> (file: Data, vault: UnlockedVault, code: RecoveryCode) {
    let (vault, code) = try UnlockedVault.create(password: "correct horse", deviceKey: thisMac, parameters: fast)
    return (try vault.seal(Data(body.utf8)), vault, code)
  }

  @Test("パスワードとこの Mac の鍵がそろえば開ける")
  func opensWithPasswordAndDeviceKey() throws {
    // Given
    let (file, _, _) = try makeFile()

    // When
    let opened = try UnlockedVault.open(file, password: "correct horse", deviceKey: thisMac)

    // Then: 形式バージョン 2 で、ヘッダは決まった長さ
    #expect(String(decoding: opened.plaintext, as: UTF8.self) == "秘密のメモ")
    #expect(opened.vault.protection == .deviceBound)
    #expect(try UnlockedVault.protection(ofFile: file) == .deviceBound)
    #expect(file[4] == 2)
    #expect(file.count == VaultFile.deviceBoundHeaderLength + "秘密のメモ".utf8.count + VaultFile.tagLength)
  }

  @Test("ほかの Mac にコピーしたファイルは、正しいパスワードでも開けない")
  func copiedFileNeedsThisMac() throws {
    // Given
    let (file, _, _) = try makeFile()
    let otherMac = P256.KeyAgreement.PrivateKey()

    // When / Then: 別の Mac の鍵でも、鍵なしでも開けない
    #expect(throws: VaultError.authenticationFailed) {
      try UnlockedVault.open(file, password: "correct horse", deviceKey: otherMac)
    }
    #expect(throws: VaultError.deviceKeyRequired) { try UnlockedVault.open(file, password: "correct horse") }
  }

  @Test("この Mac でも、パスワードが違えば開けない")
  func wrongPasswordFails() throws {
    // Given
    let (file, vault, _) = try makeFile()

    // When / Then
    #expect(throws: VaultError.authenticationFailed) {
      try UnlockedVault.open(file, password: "Correct horse", deviceKey: thisMac)
    }
    #expect(vault.verifies(password: "correct horse", deviceKey: thisMac))
    #expect(!vault.verifies(password: "correct horse"))
    #expect(!vault.verifies(password: "wrong", deviceKey: thisMac))
  }

  @Test("Mac の鍵がなくても、復旧コードなら開ける")
  func recoveryCodeOpens() throws {
    // Given
    let (file, _, code) = try makeFile()

    // When: 控えた文字列を打ち直して開く
    let typed = try #require(RecoveryCode(code.description.lowercased()))
    let opened = try UnlockedVault.open(file, recoveryCode: typed)

    // Then
    #expect(String(decoding: opened.plaintext, as: UTF8.self) == "秘密のメモ")
  }

  @Test("違う復旧コードでは開けず、パスワードだけの金庫には復旧コードがない")
  func wrongRecoveryCodeFails() throws {
    // Given
    let (file, _, _) = try makeFile()
    let passwordOnly = try UnlockedVault.create(password: "correct horse", parameters: fast).seal(Data())

    // When / Then
    #expect(throws: VaultError.recoveryFailed) { try UnlockedVault.open(file, recoveryCode: .random()) }
    #expect(throws: VaultError.notDeviceBound) { try UnlockedVault.open(passwordOnly, recoveryCode: .random()) }
  }

  /// 鍵の作り方・使い捨ての公開鍵・包んだ鍵・本文の nonce のどれを書き換えても、改ざんに気づく
  @Test("ヘッダのどの 1 バイトを書き換えても開けない")
  func detectsHeaderTampering() throws {
    // Given
    let (file, _, _) = try makeFile()

    for index in 0..<VaultFile.deviceBoundHeaderLength {
      // When
      var tampered = file
      tampered[index] ^= 0x01

      // Then: パスワードでも復旧コードでも開けない（エラーの種類は場所による）
      #expect(throws: (any Error).self, "位置 \(index)") {
        try UnlockedVault.open(tampered, password: "correct horse", deviceKey: thisMac)
      }
    }
  }

  @Test("この Mac 専用にすると、パスワードだけでは開けなくなり、解除すると戻る")
  func bindAndUnbind() throws {
    // Given: パスワードだけの金庫
    let original = try UnlockedVault.create(password: "correct horse", parameters: fast)

    // When: この Mac 専用にし、さらに解除する
    let (bound, code) = try original.rekeyed(password: "correct horse", deviceKey: thisMac, parameters: fast)
    let boundFile = try bound.seal(Data("A".utf8))
    let (unbound, noCode) = try bound.rekeyed(password: "correct horse", deviceKey: nil, parameters: fast)
    let unboundFile = try unbound.seal(Data("B".utf8))

    // Then
    #expect(code != nil)
    #expect(bound.protection == .deviceBound)
    #expect(throws: VaultError.deviceKeyRequired) { try UnlockedVault.open(boundFile, password: "correct horse") }
    #expect(noCode == nil)
    #expect(unbound.protection == .password)
    #expect(try UnlockedVault.open(unboundFile, password: "correct horse").plaintext == Data("B".utf8))
  }

  @Test("作り直すと復旧コードも新しくなり、古い復旧コードでは新しいファイルを開けない")
  func rekeyReplacesRecoveryCode() throws {
    // Given
    let (_, vault, oldCode) = try makeFile()

    // When: パスワードを変える
    let (changed, newCode) = try vault.rekeyed(password: "battery staple", deviceKey: thisMac, parameters: fast)
    let file = try changed.seal(Data("新しい中身".utf8))

    // Then
    let code = try #require(newCode)
    #expect(code != oldCode)
    #expect(changed.identifier != vault.identifier)
    #expect(throws: VaultError.recoveryFailed) { try UnlockedVault.open(file, recoveryCode: oldCode) }
    #expect(try UnlockedVault.open(file, recoveryCode: code).plaintext == Data("新しい中身".utf8))
    #expect(try UnlockedVault.open(file, password: "battery staple", deviceKey: thisMac).plaintext == Data("新しい中身".utf8))
  }

  @Test("Secure Enclave の本物の鍵でも作って開ける", .enabled(if: SecureEnclave.isAvailable))
  func realSecureEnclave() throws {
    // Given: 指紋なしで使える Secure Enclave の鍵
    let key = try SecureEnclave.P256.KeyAgreement.PrivateKey()
    let (vault, _) = try UnlockedVault.create(password: "correct horse", deviceKey: key, parameters: fast)
    let file = try vault.seal(Data("本物".utf8))

    // When: 鍵をファイルに残す形にして、読み戻す
    let restored = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: key.dataRepresentation)

    // Then
    #expect(try UnlockedVault.open(file, password: "correct horse", deviceKey: restored).plaintext == Data("本物".utf8))
  }
}

@Suite("復旧コード")
struct RecoveryCodeTests {
  @Test("4 文字ずつ 6 組で見せ、読み戻すと同じ値になる")
  func formatsAndParses() throws {
    // Given
    let code = RecoveryCode.random()

    // When
    let text = code.description
    let parsed = try #require(RecoveryCode(text))

    // Then
    #expect(text.split(separator: "-").map(\.count) == [4, 4, 4, 4, 4, 4])
    #expect(parsed == code)
  }

  @Test("区切り・空白・小文字を気にせず、見間違えやすい文字は読み替える", arguments: [
    "0000-0000-0000-0000-0000-0001",
    "0000 0000 0000 0000 0000 0001",
    "oooo-oooo-oooo-oooo-oooo-oooI",
    "OOOOOOOOOOOOOOOOOOOOOOOL",
  ])
  func toleratesTypos(text: String) throws {
    // Given / When
    let code = try #require(RecoveryCode(text))

    // Then: 最後のビットだけが 1
    #expect(code.bytes == Data(repeating: 0, count: 14) + Data([1]))
  }

  @Test("文字数が違うものや、使わない文字を含むものは受け付けない", arguments: [
    "",
    "0000-0000-0000-0000-0000-000",
    "0000-0000-0000-0000-0000-00000",
    "0000-0000-0000-0000-0000-000U",
    "0000-0000-0000-0000-0000-000!",
  ])
  func rejectsMalformed(text: String) {
    // Given / When
    let code = RecoveryCode(text)

    // Then
    #expect(code == nil)
  }
}

@Suite("Touch ID で開くための token")
struct QuickUnlockTokenTests {
  private let fast = KDFParameters(memoryKiB: 8, iterations: 1)
  /// Touch ID が要る Secure Enclave の鍵の代わり
  private let touchIDKey = P256.KeyAgreement.PrivateKey()

  @Test("token と、それを包んだ鍵があれば、パスワードなしで開ける", arguments: [false, true])
  func opensWithToken(deviceBound: Bool) throws {
    // Given: パスワードだけの金庫と、この Mac 専用の金庫の両方
    let vault =
      deviceBound
      ? try UnlockedVault.create(password: "correct horse", deviceKey: P256.KeyAgreement.PrivateKey(), parameters: fast).vault
      : try UnlockedVault.create(password: "correct horse", parameters: fast)
    let file = try vault.seal(Data("中身".utf8))
    let token = try vault.quickUnlockToken(using: touchIDKey)

    // When: 保存して読み戻した token で開く
    let stored = try JSONDecoder().decode(QuickUnlockToken.self, from: JSONEncoder().encode(token))
    let opened = try UnlockedVault.open(file, token: stored, tokenKey: touchIDKey)

    // Then: 開いた金庫は元と同じ形（保存し直しても同じ形式のまま）
    #expect(opened.plaintext == Data("中身".utf8))
    #expect(opened.vault.protection == vault.protection)
    #expect(opened.vault.identifier == vault.identifier)
  }

  @Test("別の鍵や、別の金庫の token では開けない")
  func tokenIsBoundToKeyAndVault() throws {
    // Given
    let a = try UnlockedVault.create(password: "correct horse", parameters: fast)
    let b = try UnlockedVault.create(password: "correct horse", parameters: fast)
    let fileB = try b.seal(Data("B".utf8))
    let tokenA = try a.quickUnlockToken(using: touchIDKey)
    let tokenB = try b.quickUnlockToken(using: touchIDKey)

    // When / Then
    #expect(throws: VaultError.authenticationFailed) {
      try UnlockedVault.open(fileB, token: tokenB, tokenKey: P256.KeyAgreement.PrivateKey())
    }
    #expect(throws: VaultError.authenticationFailed) { try UnlockedVault.open(fileB, token: tokenA, tokenKey: touchIDKey) }
  }
}
