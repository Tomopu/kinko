import CryptoKit
import Foundation
import KinkoCore

/// 新しい版を自分で入れる。順番が大事で、確かめる前のものは開かない：
/// 1. 書き付け（.sig）を取り、アプリに埋め込んだ公開鍵で署名を確かめ、このリリースのものかを見る
/// 2. DMG を取り、大きさと SHA-256 が書き付けと同じかを見る（ここで初めて DMG を信じる）
/// 3. DMG を読み取り専用でつなぎ、中の Kinko.app を写して、名前（bundle id）・版・コード署名を確かめる
/// 4. Kinko が終わるのを待って入れ替える小さな処理を動かし、Kinko を終える
/// アプリがダウンロードしたものには「インターネットから来た」印が付かないので、入れ替えた版は確認なしで開ける。
/// その代わり、信じてよいかは 1・2 の署名で決める
enum UpdateInstaller {
  struct Prepared: Equatable, Sendable {
    var version: AppVersion
    /// 入れ替えるアプリ（今動いている Kinko.app）
    var target: URL
    /// 確かめ終えた新しい Kinko.app
    var app: URL
    /// 作業用のフォルダ（入れ替えに成功したら消す）
    var work: URL
    /// 自動で入れ替えられなかったときに、手で入れてもらうための DMG
    var dmg: URL
  }

  /// 入れ替えられる場所にあるかを確かめ、入れ替えるアプリの場所を返す
  static func target(_ bundle: URL = Bundle.main.bundleURL) throws -> URL {
    guard bundle.pathExtension == "app" else { throw UpdateError.cannotInstall("アプリとして動いていません。") }
    // ダウンロードしたまま（DMG の中やダウンロードフォルダ）で開くと、macOS が読み取り専用の場所へ移して動かす
    if bundle.path.contains("/AppTranslocation/") {
      throw UpdateError.cannotInstall("Kinko をアプリケーションフォルダへ移してから開き直してください。")
    }
    let readOnly = (try? bundle.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) ?? true
    let manager = FileManager.default
    guard !readOnly, manager.isWritableFile(atPath: bundle.deletingLastPathComponent().path), manager.isWritableFile(atPath: bundle.path) else {
      throw UpdateError.cannotInstall("Kinko のある場所に書き込めません。")
    }
    return bundle
  }

  /// 1〜3 をする。progress には今していることと、分かれば進み具合（0〜1）を渡す
  static func prepare(
    _ release: Release, current: AppVersion, publicKey: Curve25519.Signing.PublicKey, target: URL, bundleID: String,
    progress: @escaping @Sendable (String, Double?) async -> Void
  ) async throws -> Prepared {
    guard release.isNewer(than: current), let dmgURL = release.dmg, let signatureURL = release.signature else {
      throw UpdateError.cannotInstall("このリリースには署名がありません。")
    }
    let session = URLSession(configuration: configuration)
    defer { session.finishTasksAndInvalidate() }

    await progress("署名を確かめています…", nil)
    let signature = try await download(signatureURL, limit: UpdateManifest.maxLength, session: session)
    let manifest = try UpdateManifest.verified(signature, publicKey: publicKey)
    guard manifest.matches(release) else { throw UpdateError.badSignature }

    // 作業用のフォルダは入れ替える先と同じボリュームに作る（最後の入れ替えを、写さずに名前の付け替えだけで済ませる）
    let manager = FileManager.default
    let work = try manager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: target, create: true)
    do {
      let dmg = work.appending(path: manifest.file)
      try await download(dmgURL, to: dmg, size: manifest.size, session: session) { await progress("ダウンロードしています…", $0) }
      await progress("中身を確かめています…", nil)
      guard try manifest.matches(dmg: dmg) else { throw UpdateError.badSignature }

      let app = try await extractApp(from: dmg, into: work)
      try await check(app, bundleID: bundleID, version: manifest.version)
      return Prepared(version: release.version, target: target, app: app, work: work, dmg: dmg)
    } catch {
      try? manager.removeItem(at: work)
      throw error
    }
  }

  /// 4. Kinko（pid）が終わるのを待ってから入れ替える処理を、別のプロセスとして動かす。
  /// 失敗したら元の版に戻し、元の版を開き直して、手で入れられるように DMG を開く
  static func launchSwap(_ prepared: Prepared, pid: Int32 = ProcessInfo.processInfo.processIdentifier, relaunch: Bool = true) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    // 場所は引数で渡し、スクリプトの文には埋め込まない（名前に記号があっても命令として読まれない）
    process.arguments = [
      "-c", swapScript, "kinko-update", String(pid), prepared.target.path, prepared.app.path, prepared.work.path,
      prepared.dmg.path, relaunch ? "1" : "0",
    ]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
  }

  static let swapScript = """
    pid="$1"; target="$2"; new="$3"; work="$4"; dmg="$5"; relaunch="$6"
    # Kinko が終わるのを待つ（終了が取り消されたら、2 分であきらめて何もしない）
    i=0
    while kill -0 "$pid" 2>/dev/null; do
      sleep 0.2; i=$((i + 1))
      [ "$i" -gt 600 ] && exit 1
    done
    backup="$work/old.app"
    if mv "$target" "$backup"; then
      if mv "$new" "$target"; then
        rm -rf "$work"
        [ "$relaunch" = 1 ] && open "$target"
        exit 0
      fi
      mv "$backup" "$target"
    fi
    [ "$relaunch" = 1 ] && open "$target" && open "$dmg"
    exit 1
    """

  // MARK: - 内部

  private static var configuration: URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 30
    configuration.httpCookieStorage = nil
    configuration.urlCache = nil
    return configuration
  }

  private static func download(_ url: URL, limit: Int, session: URLSession) async throws -> Data {
    let data: Data, response: URLResponse
    do {
      (data, response) = try await session.data(from: url)
    } catch {
      throw UpdateError.network(error.localizedDescription)
    }
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.network("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)") }
    guard data.count <= limit else { throw UpdateError.badSignature }
    return data
  }

  /// 書き付けにある大きさまでだけ受け取る（それより大きいものを送られても、ディスクを埋めない）
  private static func download(
    _ url: URL, to file: URL, size: Int, session: URLSession, progress: @escaping @Sendable (Double) async -> Void
  ) async throws {
    let bytes: URLSession.AsyncBytes, response: URLResponse
    do {
      (bytes, response) = try await session.bytes(from: url)
    } catch {
      throw UpdateError.network(error.localizedDescription)
    }
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.network("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)") }
    guard FileManager.default.createFile(atPath: file.path, contents: nil) else { throw UpdateError.cannotInstall("一時ファイルを作れません。") }
    let handle = try FileHandle(forWritingTo: file)
    defer { try? handle.close() }
    var buffer = Data()
    buffer.reserveCapacity(1 << 20)
    var written = 0
    do {
      for try await byte in bytes {
        buffer.append(byte)
        if buffer.count == 1 << 20 {
          written += buffer.count
          guard written <= size else { throw UpdateError.badSignature }
          try handle.write(contentsOf: buffer)
          buffer.removeAll(keepingCapacity: true)
          await progress(Double(written) / Double(size))
        }
      }
    } catch let error as UpdateError {
      throw error
    } catch {
      throw UpdateError.network(error.localizedDescription)
    }
    written += buffer.count
    guard written <= size else { throw UpdateError.badSignature }
    try handle.write(contentsOf: buffer)
    await progress(1)
  }

  /// DMG を Finder に出さず読み取り専用でつなぎ、中の Kinko.app を作業用のフォルダへ写す
  private static func extractApp(from dmg: URL, into work: URL) async throws -> URL {
    let mount = work.appending(path: "mount")
    try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
    try await run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, dmg.path])
    do {
      let source = mount.appending(path: "Kinko.app")
      let isLink = (try? source.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? true
      guard !isLink, FileManager.default.fileExists(atPath: source.path) else { throw UpdateError.badSignature }
      let app = work.appending(path: "Kinko.app")
      try await run("/usr/bin/ditto", [source.path, app.path])
      _ = try? await run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet"])
      return app
    } catch {
      _ = try? await run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet", "-force"])
      throw error
    }
  }

  /// 写したアプリが、同じアプリ（bundle id）の書き付けどおりの版で、コード署名が壊れていないか
  private static func check(_ app: URL, bundleID: String, version: String) async throws {
    let plist = app.appending(path: "Contents/Info.plist")
    guard let data = try? Data(contentsOf: plist),
      let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
      info["CFBundleIdentifier"] as? String == bundleID,
      (info["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init) == AppVersion(version)
    else { throw UpdateError.badSignature }
    do {
      try await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
    } catch {
      throw UpdateError.badSignature
    }
  }

  @discardableResult
  private static func run(_ tool: String, _ arguments: [String]) async throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    let status: Int32 = try await withCheckedThrowingContinuation { continuation in
      process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
      do {
        try process.run()
      } catch {
        process.terminationHandler = nil
        continuation.resume(throwing: error)
      }
    }
    guard status == 0 else { throw UpdateError.cannotInstall("\((tool as NSString).lastPathComponent) が失敗しました（\(status)）。") }
    return status
  }
}

#if DEBUG
extension UpdateInstaller {
  /// 開発用の通し試験：`Kinko --update-install-test <配布元の URL> <版> <DMG の名前> <結果のファイル>`。
  /// 本物の Kinko.app の中で動かし、書き付けと DMG を配布元から取って確かめ、入れ替えの処理を動かして終わる（開き直さない）
  @MainActor
  static func runInstallTestIfRequested() {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: "--update-install-test"), index + 4 < arguments.count else { return }
    let base = URL(string: arguments[index + 1])!, version = AppVersion(arguments[index + 2])!, name = arguments[index + 3]
    let log = URL(fileURLWithPath: arguments[index + 4])
    func write(_ text: String) { try? Data((text + "\n").utf8).write(to: log) }
    let bundle = Bundle.main
    let release = Release(
      version: version, title: "", notes: "", page: base, dmg: base.appending(path: name), signature: base.appending(path: name + ".sig"))
    Task {
      do {
        let checker = UpdateChecker()
        guard let key = checker.publicKey, let current = checker.current, let id = bundle.bundleIdentifier else { return write("no key") }
        let prepared = try await prepare(release, current: current, publicKey: key, target: target(), bundleID: id) { _, _ in }
        try launchSwap(prepared, relaunch: false)
        write("launched \(prepared.app.path)")
      } catch {
        write("failed \(error.localizedDescription)")
      }
      exit(0)
    }
    RunLoop.main.run(until: Date().addingTimeInterval(120))
    write("timeout")
    exit(1)
  }
}
#endif
