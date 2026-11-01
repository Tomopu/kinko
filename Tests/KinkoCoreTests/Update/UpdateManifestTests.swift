import CryptoKit
import Foundation
import Testing

@testable import KinkoCore

@Suite("更新の書き付けの署名")
struct UpdateManifestTests {
  /// テストのたびに作る使い捨ての鍵と、中身が決まった DMG もどき
  private func signed(version: String = "0.16.0", file: String = "Kinko-0.16.0.dmg") throws -> (UpdateManifest, URL, Curve25519.Signing.PrivateKey) {
    let key = Curve25519.Signing.PrivateKey()
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let dmg = directory.appending(path: file)
    try Data("DMG の中身".utf8).write(to: dmg)
    return (try UpdateManifest.make(dmg: dmg, version: version, key: key), dmg, key)
  }

  private func release(_ version: String = "0.16.0", dmg: String = "Kinko-0.16.0.dmg") -> Release {
    let base = "https://github.com/Tomopu/kinko/releases/download/v\(version)/"
    return Release(
      version: AppVersion(version)!, title: "", notes: "", page: URL(string: "https://github.com/Tomopu/kinko")!,
      dmg: URL(string: base + dmg), signature: URL(string: base + dmg + ".sig"))
  }

  @Test("署名した書き付けは、対になる公開鍵で確かめられ、同じ DMG・同じリリースに合う")
  func roundTrip() throws {
    // Given
    let (manifest, dmg, key) = try signed()

    // When
    let verified = try UpdateManifest.verified(manifest.encoded(), publicKey: key.publicKey)

    // Then
    #expect(verified == manifest)
    #expect(try verified.matches(dmg: dmg))
    #expect(verified.matches(release()))
  }

  @Test("別の鍵の署名や、署名のあとで書き換えた書き付けは断る")
  func rejectsForgery() throws {
    // Given
    let (manifest, _, _) = try signed()
    let other = Curve25519.Signing.PrivateKey()
    var tampered = manifest
    tampered.sha256 = String(repeating: "0", count: 64)

    // When / Then
    #expect(throws: UpdateError.badSignature) { try UpdateManifest.verified(manifest.encoded(), publicKey: other.publicKey) }
    #expect(throws: UpdateError.badSignature) {
      try UpdateManifest.verified(tampered.encoded(), publicKey: Curve25519.Signing.PrivateKey().publicKey)
    }
    #expect(throws: UpdateError.badSignature) { try UpdateManifest.verified(Data("<html>".utf8), publicKey: other.publicKey) }
  }

  @Test("書き換えた中身の書き付けは、元の鍵でも断る")
  func rejectsTamperingWithOriginalKey() throws {
    // Given
    let (manifest, _, key) = try signed()
    var bigger = manifest
    bigger.size += 1

    // When / Then
    #expect(throws: UpdateError.badSignature) { try UpdateManifest.verified(bigger.encoded(), publicKey: key.publicKey) }
  }

  @Test("中身が 1 バイトでも違う DMG は合わない")
  func detectsChangedDMG() throws {
    // Given
    let (manifest, dmg, _) = try signed()

    // When
    try Data("DMG の中身!".utf8).write(to: dmg)

    // Then
    #expect(try !manifest.matches(dmg: dmg))
  }

  @Test("古い版の正しい書き付けを、新しいリリースのものとしては使えない")
  func bindsToRelease() throws {
    // Given
    let (old, _, key) = try signed(version: "0.15.0", file: "Kinko-0.15.0.dmg")

    // When
    let verified = try UpdateManifest.verified(old.encoded(), publicKey: key.publicKey)

    // Then
    #expect(!verified.matches(release("0.16.0")))
    #expect(!verified.matches(release("0.15.0", dmg: "Other.dmg")))
    #expect(verified.matches(release("0.15.0", dmg: "Kinko-0.15.0.dmg")))
  }

  @Test("公開鍵は Base64 の 32 バイトだけを読む", arguments: ["", "abc", Data(repeating: 1, count: 31).base64EncodedString()])
  func rejectsMalformedPublicKey(text: String) {
    // Given / When / Then
    #expect(UpdateManifest.publicKey(base64: text) == nil)
  }

  @Test("公開鍵は前後の空白や改行があっても読める")
  func readsPublicKey() {
    // Given
    let key = Curve25519.Signing.PrivateKey().publicKey

    // When
    let read = UpdateManifest.publicKey(base64: " \(key.rawRepresentation.base64EncodedString())\n")

    // Then
    #expect(read?.rawRepresentation == key.rawRepresentation)
  }
}
