import CryptoKit
import Foundation

/// 更新の書き付け。配る DMG の版・名前・大きさ・SHA-256 を、配る人の秘密鍵（Ed25519）で署名したもの。
/// リリースに `<DMG の名前>.sig` として DMG と一緒に置く。アプリは埋め込んだ公開鍵で署名を確かめてから DMG を信じる。
/// GitHub のリリースを書き換えられる人でも、秘密鍵がなければ別の DMG を正しいものに見せかけられない
public struct UpdateManifest: Codable, Equatable, Sendable {
  public var version: String
  public var file: String
  public var size: Int
  /// 小文字の 16 進
  public var sha256: String
  /// signedMessage に対する Ed25519 の署名（Base64）
  public var signature: String

  /// 書き付けの形式。ほかの用途の署名と取り違えないよう、署名する文の先頭に入れる
  static let domain = "kinko-update-v1"
  /// 書き付け（.sig）の大きさの上限。ふつうは 300 バイトほど
  public static let maxLength = 4_096
  /// DMG の大きさの上限。ふつうは数 MB
  public static let maxDMGSize = 512 * 1_024 * 1_024

  /// 署名する文。項目を決まった順に改行でつなぐ（JSON の並びや空白の違いで署名が変わらないように）
  var signedMessage: Data {
    Data("\(Self.domain)\n\(version)\n\(file)\n\(size)\n\(sha256)\n".utf8)
  }

  /// DMG に署名して書き付けを作る（配る人の Mac で、リリースを作るときに使う）
  public static func make(dmg: URL, version: String, key: Curve25519.Signing.PrivateKey) throws -> UpdateManifest {
    guard AppVersion(version) != nil else { throw UpdateError.unreadable }
    let size = try dmg.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    var manifest = UpdateManifest(
      version: version, file: dmg.lastPathComponent, size: size, sha256: try sha256(of: dmg), signature: "")
    manifest.signature = try key.signature(for: manifest.signedMessage).base64EncodedString()
    return manifest
  }

  /// 書き付けを読み、署名を確かめる。署名が合わない・形がおかしいものは断る
  public static func verified(_ data: Data, publicKey: Curve25519.Signing.PublicKey) throws -> UpdateManifest {
    guard data.count <= maxLength, let manifest = try? JSONDecoder().decode(UpdateManifest.self, from: data) else {
      throw UpdateError.badSignature
    }
    guard let signature = Data(base64Encoded: manifest.signature),
      publicKey.isValidSignature(signature, for: manifest.signedMessage)
    else { throw UpdateError.badSignature }
    // 署名が合っていても、こちらが扱えない値なら使わない
    guard AppVersion(manifest.version) != nil, (1...maxDMGSize).contains(manifest.size),
      manifest.sha256.count == 64, manifest.sha256.allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
      manifest.file.lowercased().hasSuffix(".dmg"), !manifest.file.contains("/")
    else { throw UpdateError.badSignature }
    return manifest
  }

  /// 書き付けが、このリリースのこの DMG のものか（古い版の正しい書き付けを使い回されないように）
  public func matches(_ release: Release) -> Bool {
    AppVersion(version) == release.version && release.dmg?.lastPathComponent == file
  }

  /// ダウンロードした DMG が、書き付けのものと同じか
  public func matches(dmg: URL) throws -> Bool {
    let size = try dmg.resourceValues(forKeys: [.fileSizeKey]).fileSize
    guard size == self.size else { return false }
    return try Self.sha256(of: dmg) == sha256
  }

  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(self)
  }

  /// ファイルの SHA-256（小文字の 16 進）。大きなファイルでもメモリに全部は読まない
  public static func sha256(of url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
      hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  /// Info.plist に書く公開鍵（Base64 の 32 バイト）を読む
  public static func publicKey(base64: String) -> Curve25519.Signing.PublicKey? {
    Data(base64Encoded: base64.trimmingCharacters(in: .whitespacesAndNewlines))
      .flatMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }
  }
}
