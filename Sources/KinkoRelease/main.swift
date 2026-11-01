import CryptoKit
import Foundation
import KinkoCore

/// 配る人だけが使う道具：アップデートの署名の鍵を作り、DMG に署名する。
///   swift run kinko-release keygen                 鍵を作り、Info.plist に書く公開鍵を出す
///   swift run kinko-release public-key             公開鍵を出す
///   swift run kinko-release sign <DMG> <版> [<Info.plist の公開鍵>]   <DMG>.sig を作る
///   swift run kinko-release verify <DMG> <.sig> <公開鍵>             署名を確かめる
/// 秘密鍵は KINKO_SIGNING_KEY の場所（既定は ~/Library/Application Support/Kinko Release/update-signing.key）に、
/// 自分だけが読める権限で置く。リポジトリには入れない。なくすと自動の更新を届けられず、漏れると偽の更新を作られる
enum ReleaseTool {
  static var keyURL: URL {
    if let path = ProcessInfo.processInfo.environment["KINKO_SIGNING_KEY"], !path.isEmpty {
      return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }
    return FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/Application Support/Kinko Release/update-signing.key")
  }

  static func main() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    switch arguments.first {
    case "keygen": try keygen()
    case "public-key": print(try loadKey().publicKey.rawRepresentation.base64EncodedString())
    case "sign" where (3...4).contains(arguments.count):
      try sign(dmg: URL(fileURLWithPath: arguments[1]), version: arguments[2], expected: arguments.count == 4 ? arguments[3] : nil)
    case "verify" where arguments.count == 4:
      try verify(dmg: URL(fileURLWithPath: arguments[1]), signature: URL(fileURLWithPath: arguments[2]), publicKey: arguments[3])
    default:
      fail("使い方: kinko-release keygen | public-key | sign <DMG> <版> [<公開鍵>] | verify <DMG> <.sig> <公開鍵>")
    }
  }

  /// 鍵を作る。すでにあるときは上書きしない（上書きすると、配った版へ更新を届けられなくなる）
  static func keygen() throws {
    let url = keyURL
    guard !FileManager.default.fileExists(atPath: url.path) else {
      fail("鍵はもうあります: \(url.path)\n作り直すと、今の公開鍵を入れて配った版には自動の更新を届けられなくなります。")
    }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let key = Curve25519.Signing.PrivateKey()
    // 作るときから自分だけが読める権限にする（書いてから権限を変えると、その間だけほかの人に読める）
    guard FileManager.default.createFile(
      atPath: url.path, contents: Data(key.rawRepresentation.base64EncodedString().utf8), attributes: [.posixPermissions: 0o600])
    else { fail("鍵を書き込めませんでした: \(url.path)") }
    print("秘密鍵: \(url.path)（別の安全な場所にも控えてください）")
    print("Info.plist の KinkoUpdatePublicKey に書く公開鍵:")
    print(key.publicKey.rawRepresentation.base64EncodedString())
  }

  static func loadKey() throws -> Curve25519.Signing.PrivateKey {
    let url = keyURL
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
      fail("鍵がありません: \(url.path)\n`kinko-release keygen` で作ってください。")
    }
    let permissions = (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) ?? 0
    guard permissions & 0o077 == 0 else { fail("鍵がほかの人にも読める権限になっています。chmod 600 \(url.path) で直してください。") }
    guard let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
    else { fail("鍵の形が正しくありません: \(url.path)") }
    return key
  }

  /// DMG に署名して <DMG>.sig を書く。expected があれば、アプリに埋め込んだ公開鍵と対になる鍵かを先に確かめる
  static func sign(dmg: URL, version: String, expected: String?) throws {
    let key = try loadKey()
    if let expected {
      guard UpdateManifest.publicKey(base64: expected)?.rawRepresentation == key.publicKey.rawRepresentation else {
        fail("この鍵は、アプリの Info.plist の公開鍵と対になっていません。この鍵で署名しても、アプリは更新を断ります。")
      }
    }
    let manifest = try UpdateManifest.make(dmg: dmg, version: version, key: key)
    let output = dmg.appendingPathExtension("sig")
    try manifest.encoded().write(to: output)
    // 書いたものを、配る人の側でも一度確かめておく
    _ = try UpdateManifest.verified(Data(contentsOf: output), publicKey: key.publicKey)
    print("signed \(output.path)")
  }

  static func verify(dmg: URL, signature: URL, publicKey: String) throws {
    guard let key = UpdateManifest.publicKey(base64: publicKey) else { fail("公開鍵の形が正しくありません。") }
    let manifest = try UpdateManifest.verified(Data(contentsOf: signature), publicKey: key)
    guard manifest.file == dmg.lastPathComponent, try manifest.matches(dmg: dmg) else { fail("署名は正しいが、DMG と合いません。") }
    print("ok \(manifest.file) \(manifest.version)")
  }

  static func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
  }
}

do {
  try ReleaseTool.main()
} catch {
  ReleaseTool.fail(error.localizedDescription)
}
