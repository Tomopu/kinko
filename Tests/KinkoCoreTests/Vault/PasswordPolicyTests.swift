import Testing

@testable import KinkoCore

@Test func asciiPassphrasesAreAccepted() throws {
  try PasswordPolicy.validate("correct horse battery staple")
  try PasswordPolicy.validate("sakura-umi-15!~")
  try PasswordPolicy.validate("12345678")
}

@Test func shortPasswordsAreRejected() {
  #expect(throws: PasswordPolicy.Violation.tooShort) { try PasswordPolicy.validate("") }
  #expect(throws: PasswordPolicy.Violation.tooShort) { try PasswordPolicy.validate("1234567") }
}

/// 日本語・全角英数字・全角空白・絵文字・改行やタブは使えない
@Test func nonASCIICharactersAreRejected() {
  for password in ["こんにちはこんにちは", "ｐａｓｓｗｏｒｄ１２", "pass　word123", "password🔑123", "pass\tword123", "pass\nword123", "kkおnんいttいhhあ"] {
    #expect(throws: PasswordPolicy.Violation.unsupportedCharacters, "\(password)") {
      try PasswordPolicy.validate(password)
    }
  }
}
