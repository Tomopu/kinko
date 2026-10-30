import Foundation
import Testing

@testable import KinkoCore

/// テストでは Argon2id を最小の重さにして速く回す
private let fast = KDFParameters(memoryKiB: 8, iterations: 1)

private func makeFile(password: String = "correct horse", body: String = "秘密のメモ") throws -> Data {
  try UnlockedVault.create(password: password, parameters: fast).seal(Data(body.utf8))
}

@Test func roundTripWithJapanesePassword() throws {
  let file = try makeFile(password: "日本語のパスワード🔑", body: "口座番号は書かない")
  let (_, plaintext) = try UnlockedVault.open(file, password: "日本語のパスワード🔑")
  #expect(String(decoding: plaintext, as: UTF8.self) == "口座番号は書かない")
}

@Test func emptyBodyRoundTrips() throws {
  let file = try makeFile(body: "")
  #expect(try UnlockedVault.open(file, password: "correct horse").plaintext.isEmpty)
  #expect(file.count == VaultFile.headerLength + VaultFile.tagLength)
}

@Test func wrongPasswordFails() throws {
  let file = try makeFile()
  #expect(throws: VaultError.authenticationFailed) {
    try UnlockedVault.open(file, password: "Correct horse")
  }
}

@Test func emptyPasswordIsRejected() {
  #expect(throws: VaultError.emptyPassword) {
    try UnlockedVault.create(password: "", parameters: fast)
  }
}

/// 「が」（U+304C）と「か＋濁点」（U+304B U+3099）は同じパスワードとして扱う
@Test func passwordIsNormalized() throws {
  let file = try makeFile(password: "\u{304C}")
  #expect(throws: Never.self) { try UnlockedVault.open(file, password: "\u{304B}\u{3099}") }
}

/// どの 1 バイトを書き換えても、開けないか、開けても例外になる
@Test func everyByteIsAuthenticated() throws {
  let file = try makeFile()
  for index in file.indices {
    var tampered = file
    tampered[index] ^= 0x01
    #expect(throws: VaultError.self, "byte \(index)") {
      try UnlockedVault.open(tampered, password: "correct horse")
    }
  }
}

@Test func truncatedFileFails() throws {
  let file = try makeFile()
  for length in [0, 3, VaultFile.headerLength, file.count - 1] {
    #expect(throws: VaultError.self) {
      try UnlockedVault.open(file.prefix(length), password: "correct horse")
    }
  }
}

/// 巨大なメモリを要求する細工ファイルは、鍵導出を始める前に弾く
@Test func hugeKDFParametersAreRejected() throws {
  var file = try makeFile()
  file.replaceSubrange(6..<10, with: [0xFF, 0xFF, 0xFF, 0xFF])
  #expect(throws: VaultError.unacceptableParameters) {
    try UnlockedVault.open(file, password: "correct horse")
  }
}

@Test func otherFilesAreNotVaults() {
  #expect(throws: VaultError.notAVault) {
    try UnlockedVault.open(Data("hello, world".utf8), password: "x")
  }
}

/// 保存し直すと nonce と暗号文は変わるが、鍵の部分（ヘッダ前半）は変わらない
@Test func resealUsesFreshNonce() throws {
  let vault = try UnlockedVault.create(password: "correct horse", parameters: fast)
  let first = try vault.seal(Data("同じ本文".utf8))
  let second = try vault.seal(Data("同じ本文".utf8))
  let envelopeLength = VaultFile.headerLength - VaultFile.nonceLength
  #expect(first.prefix(envelopeLength) == second.prefix(envelopeLength))
  #expect(first.dropFirst(envelopeLength) != second.dropFirst(envelopeLength))
  #expect(try UnlockedVault.open(second, password: "correct horse").plaintext == Data("同じ本文".utf8))
}

/// 開いた金庫で保存し直したファイルも、同じパスワードで開ける
@Test func reopenedVaultCanSave() throws {
  let file = try makeFile()
  let (vault, _) = try UnlockedVault.open(file, password: "correct horse")
  let saved = try vault.seal(Data("書き換えた".utf8))
  let reopened = try UnlockedVault.open(saved, password: "correct horse").plaintext
  #expect(String(decoding: reopened, as: UTF8.self) == "書き換えた")
}

/// 同じパスワードでも金庫ごとに salt とデータ鍵が違うので、暗号文は似ても似つかない
@Test func vaultsDoNotShareKeys() throws {
  let a = try makeFile(), b = try makeFile()
  #expect(a.subdata(in: 14..<30) != b.subdata(in: 14..<30))
  #expect(a.dropFirst(VaultFile.headerLength) != b.dropFirst(VaultFile.headerLength))
}

/// 本番の設定で 1 回の試行にかかる時間。総当たりする側も、1 回ごとにこの時間とメモリを払う
@Test func standardParametersCost() throws {
  let start = ContinuousClock.now
  _ = try KeyDerivation.deriveKey(password: "x", salt: Data(count: 16), parameters: .standard)
  let elapsed = ContinuousClock.now - start
  print("Argon2id standard: \(elapsed)")
  #expect(elapsed < .seconds(5))
}

/// 保存したファイルのどこにも、本文やパスワードのバイト列が出てこない
@Test func fileContainsNoPlaintext() throws {
  let body = String(repeating: "マイナンバー 1234-5678 ", count: 50)
  let file = try makeFile(password: "correct horse", body: body)
  for needle in ["マイナンバー", "1234", "correct horse"] {
    #expect(file.range(of: Data(needle.utf8)) == nil, "\(needle)")
  }
}
