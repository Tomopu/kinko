import Foundation
import Testing

@testable import KinkoCore

@Suite("金庫ファイル")
struct VaultTests {
  /// テストでは Argon2id を最小の重さにして速く回す
  private let fast = KDFParameters(memoryKiB: 8, iterations: 1)

  private func makeFile(password: String = "correct horse", body: String = "秘密のメモ") throws -> Data {
    try UnlockedVault.create(password: password, parameters: fast).seal(Data(body.utf8))
  }

  @Test("日本語や絵文字のパスワードで保存したファイルを、同じパスワードで開ける")
  func roundTripWithJapanesePassword() throws {
    // Given
    let file = try makeFile(password: "日本語のパスワード🔑", body: "口座番号は書かない")

    // When
    let (_, plaintext) = try UnlockedVault.open(file, password: "日本語のパスワード🔑")

    // Then
    #expect(String(decoding: plaintext, as: UTF8.self) == "口座番号は書かない")
  }

  @Test("空の本文も保存して開け、ファイルはヘッダとタグだけになる")
  func emptyBodyRoundTrips() throws {
    // Given / When
    let file = try makeFile(body: "")

    // Then
    #expect(try UnlockedVault.open(file, password: "correct horse").plaintext.isEmpty)
    #expect(file.count == VaultFile.headerLength + VaultFile.tagLength)
  }

  @Test("1 文字でも違うパスワードでは開けない")
  func wrongPasswordFails() throws {
    // Given
    let file = try makeFile()

    // When / Then: 大文字小文字だけの違い
    #expect(throws: VaultError.authenticationFailed) {
      try UnlockedVault.open(file, password: "Correct horse")
    }
  }

  @Test("空のパスワードでは金庫を作れない")
  func emptyPasswordIsRejected() {
    // Given / When / Then
    #expect(throws: VaultError.emptyPassword) {
      try UnlockedVault.create(password: "", parameters: fast)
    }
  }

  /// 「が」（U+304C）と「か＋濁点」（U+304B U+3099）は同じパスワードとして扱う
  @Test("Unicode の正規化で同じになるパスワードなら開ける")
  func passwordIsNormalized() throws {
    // Given: 合成済みの「が」で保存
    let file = try makeFile(password: "\u{304C}")

    // When / Then: 「か＋濁点」で開ける
    #expect(throws: Never.self) { try UnlockedVault.open(file, password: "\u{304B}\u{3099}") }
  }

  @Test("どの 1 バイトを書き換えても、開くと例外になる")
  func everyByteIsAuthenticated() throws {
    // Given
    let file = try makeFile()

    for index in file.indices {
      // When: index のバイトを 1 ビットだけ反転する
      var tampered = file
      tampered[index] ^= 0x01

      // Then
      #expect(throws: VaultError.self, "byte \(index)") {
        try UnlockedVault.open(tampered, password: "correct horse")
      }
    }
  }

  @Test("途中で切れたファイルは開けない")
  func truncatedFileFails() throws {
    // Given
    let file = try makeFile()

    // When: 空・数バイト・ヘッダだけ・最後の 1 バイト欠け
    for length in [0, 3, VaultFile.headerLength, file.count - 1] {
      // Then
      #expect(throws: VaultError.self, "length \(length)") {
        try UnlockedVault.open(file.prefix(length), password: "correct horse")
      }
    }
  }

  @Test("巨大なメモリを要求する細工ファイルは、鍵導出を始める前に弾く")
  func hugeKDFParametersAreRejected() throws {
    // Given: ヘッダの memoryKiB（6〜9 バイト目）を最大にする
    var file = try makeFile()
    file.replaceSubrange(6..<10, with: [0xFF, 0xFF, 0xFF, 0xFF])

    // When / Then
    #expect(throws: VaultError.unacceptableParameters) {
      try UnlockedVault.open(file, password: "correct horse")
    }
  }

  @Test("金庫でないファイルはそう伝える")
  func otherFilesAreNotVaults() {
    // Given / When / Then
    #expect(throws: VaultError.notAVault) {
      try UnlockedVault.open(Data("hello, world".utf8), password: "x")
    }
  }

  @Test("保存し直すと nonce と暗号文は変わるが、鍵の部分（ヘッダ前半）は変わらない")
  func resealUsesFreshNonce() throws {
    // Given
    let vault = try UnlockedVault.create(password: "correct horse", parameters: fast)

    // When: 同じ本文を 2 回保存する
    let first = try vault.seal(Data("同じ本文".utf8))
    let second = try vault.seal(Data("同じ本文".utf8))

    // Then
    let envelopeLength = VaultFile.headerLength - VaultFile.nonceLength
    #expect(first.prefix(envelopeLength) == second.prefix(envelopeLength))
    #expect(first.dropFirst(envelopeLength) != second.dropFirst(envelopeLength))
    #expect(try UnlockedVault.open(second, password: "correct horse").plaintext == Data("同じ本文".utf8))
  }

  @Test("開いた金庫で保存し直したファイルも、同じパスワードで開ける")
  func reopenedVaultCanSave() throws {
    // Given: ファイルから開いた金庫
    let (vault, _) = try UnlockedVault.open(makeFile(), password: "correct horse")

    // When
    let saved = try vault.seal(Data("書き換えた".utf8))

    // Then
    let reopened = try UnlockedVault.open(saved, password: "correct horse").plaintext
    #expect(String(decoding: reopened, as: UTF8.self) == "書き換えた")
  }

  @Test("同じパスワードでも金庫ごとに salt とデータ鍵が違い、暗号文は似ても似つかない")
  func vaultsDoNotShareKeys() throws {
    // Given / When: 同じパスワード・同じ本文で 2 つ作る
    let a = try makeFile(), b = try makeFile()

    // Then: salt（14〜29 バイト目）も本文も違う
    #expect(a.subdata(in: 14..<30) != b.subdata(in: 14..<30))
    #expect(a.dropFirst(VaultFile.headerLength) != b.dropFirst(VaultFile.headerLength))
  }

  /// 総当たりする側も、1 回ごとにこの時間とメモリを払う
  @Test("本番の設定でも 1 回の鍵導出は 5 秒以内に終わる")
  func standardParametersCost() throws {
    // Given
    let start = ContinuousClock.now

    // When
    _ = try KeyDerivation.deriveKey(password: "x", salt: Data(count: 16), parameters: .standard)
    let elapsed = ContinuousClock.now - start

    // Then
    print("Argon2id standard: \(elapsed)")
    #expect(elapsed < .seconds(5))
  }

  @Test("保存したファイルのどこにも、本文やパスワードのバイト列が出てこない")
  func fileContainsNoPlaintext() throws {
    // Given / When
    let body = String(repeating: "マイナンバー 1234-5678 ", count: 50)
    let file = try makeFile(password: "correct horse", body: body)

    // Then
    for needle in ["マイナンバー", "1234", "correct horse"] {
      #expect(file.range(of: Data(needle.utf8)) == nil, "\(needle)")
    }
  }
}
