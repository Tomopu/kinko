import Foundation
import Testing

@testable import KinkoCore

@Suite("パスワードを間違えた回数")
struct UnlockAttemptsTests {
  @Test("決めた回数に達したときだけ消し、それまでは残りの回数を返す")
  func erasesAtLimit() {
    // Given: 5 回で消す設定
    var attempts = UnlockAttempts()

    // When: 4 回間違えてから、もう 1 回間違える
    let early = (1...4).map { _ in attempts.recordFailure(of: "a", limit: 5) }
    let last = attempts.recordFailure(of: "a", limit: 5)

    // Then: 消したら数え直す
    #expect(early == [.retry(remaining: 4), .retry(remaining: 3), .retry(remaining: 2), .retry(remaining: 1)])
    #expect(last == .erase)
    #expect(attempts.failures(of: "a") == 0)
  }

  @Test("消さない設定では、何回間違えても消さずに数えるだけ")
  func neverErasesWithoutLimit() {
    // Given
    var attempts = UnlockAttempts()

    // When
    let outcomes = (1...30).map { _ in attempts.recordFailure(of: "a", limit: nil) }

    // Then
    #expect(outcomes.allSatisfy { $0 == .retry(remaining: nil) })
    #expect(attempts.failures(of: "a") == 30)
  }

  @Test("開けたら数え直し、金庫ごとに別々に数える")
  func countsPerVaultAndResetsOnSuccess() {
    // Given: a を 3 回、b を 1 回間違えた
    var attempts = UnlockAttempts()
    for _ in 1...3 { _ = attempts.recordFailure(of: "a", limit: 5) }
    _ = attempts.recordFailure(of: "b", limit: 5)

    // When: a を開けた
    attempts.recordSuccess(of: "a")

    // Then
    #expect(attempts.failures(of: "a") == 0)
    #expect(attempts.failures(of: "b") == 1)
    #expect(attempts.remaining(of: "b", limit: 5) == 4)
  }

  @Test("回数を後から減らして超えていたら、次に間違えたときに消す")
  func loweredLimitErasesOnNextFailure() {
    // Given: 20 回の設定で 7 回間違えた
    var attempts = UnlockAttempts()
    for _ in 1...7 { _ = attempts.recordFailure(of: "a", limit: 20) }

    // When: 5 回に減らす
    let remaining = attempts.remaining(of: "a", limit: 5)
    let next = attempts.recordFailure(of: "a", limit: 5)

    // Then
    #expect(remaining == 1)
    #expect(next == .erase)
  }

  @Test("保存し直しても記録が引き継がれるよう、JSON で読み書きできる")
  func roundTripsThroughJSON() throws {
    // Given
    var attempts = UnlockAttempts()
    _ = attempts.recordFailure(of: "a", limit: 10)

    // When
    let decoded = try JSONDecoder().decode(UnlockAttempts.self, from: JSONEncoder().encode(attempts))

    // Then
    #expect(decoded == attempts)
  }

  @Test("金庫の印は、開く前のファイルからも開いた金庫からも同じに読め、パスワードを変えると変わる")
  func vaultIdentifier() throws {
    // Given
    let fast = KDFParameters(memoryKiB: 8, iterations: 1)
    let vault = try UnlockedVault.create(password: "correct horse", parameters: fast)
    let file = try vault.seal(Data("本文".utf8))

    // When
    let fromFile = try UnlockedVault.identifier(ofFile: file)
    let changed = try vault.changingPassword(to: "battery staple", parameters: fast)

    // Then: salt（16 バイト）の 16 進
    #expect(fromFile == vault.identifier)
    #expect(fromFile.count == 32)
    #expect(changed.identifier != vault.identifier)
    #expect(throws: VaultError.notAVault) { try UnlockedVault.identifier(ofFile: Data("hello".utf8)) }
  }
}
