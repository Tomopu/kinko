import Testing

@testable import KinkoCore

@Suite("パスワードの規則")
struct PasswordPolicyTests {
  @Test("半角の英数字・記号・空白だけで 8 文字以上なら通す", arguments: [
    "correct horse battery staple",
    "sakura-umi-15!~",
    "12345678",
  ])
  func accepted(password: String) throws {
    // Given / When / Then: 例外にならない
    try PasswordPolicy.validate(password)
  }

  @Test("8 文字に満たないパスワードは短すぎるとして断る", arguments: ["", "1234567"])
  func tooShort(password: String) {
    // Given / When / Then
    #expect(throws: PasswordPolicy.Violation.tooShort) { try PasswordPolicy.validate(password) }
  }

  @Test("日本語・全角英数字・全角空白・絵文字・改行やタブを含むと断る", arguments: [
    // 日本語・全角
    "こんにちはこんにちは",
    "ｐａｓｓｗｏｒｄ１２",
    "pass　word123",
    "kkおnんいttいhhあ",
    // 絵文字
    "password🔑123",
    // 制御文字
    "pass\tword123",
    "pass\nword123",
  ])
  func unsupportedCharacters(password: String) {
    // Given / When / Then
    #expect(throws: PasswordPolicy.Violation.unsupportedCharacters) { try PasswordPolicy.validate(password) }
  }
}
