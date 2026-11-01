import AppKit
import CryptoKit
import Foundation
import KinkoCore

/// 「アップデートを確認…」を押したときだけ、GitHub の最新のリリースを調べる。自分からは通信しない。
/// 送るのは決まった URL への GET だけで、金庫や設定の情報は何も送らない（GitHub には IP アドレスと版が見える）
@MainActor
@Observable
final class UpdateChecker {
  enum State: Equatable {
    case idle
    case checking
    case upToDate(AppVersion)
    case available(Release)
    case failed(String)
  }

  /// 自動での入れ替えの進み具合
  enum Install: Equatable {
    case idle
    /// していること（「ダウンロードしています…」など）と、分かれば進み具合（0〜1）
    case working(String, Double?)
    /// 確かめ終え、再起動すれば入れ替えられる
    case ready(UpdateInstaller.Prepared)
    case failed(String)
    /// ダウンロードしたものが署名と合わなかった。差し替えられているかもしれないので、手で入れることも勧めない
    case rejected
  }

  private(set) var state = State.idle
  private(set) var install = Install.idle
  let current: AppVersion?
  /// "owner/repo"。Info.plist の KinkoUpdateRepository で決める
  let repository: String?
  /// 更新の書き付けの署名を確かめる公開鍵。Info.plist の KinkoUpdatePublicKey で決める。なければ自動では入れない
  let publicKey: Curve25519.Signing.PublicKey?
  private let bundleID: String?
  private var installTask: Task<Void, Never>?

  init(bundle: Bundle = .main) {
    current = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
    repository = (bundle.object(forInfoDictionaryKey: "KinkoUpdateRepository") as? String).flatMap(Self.validRepository)
    publicKey = (bundle.object(forInfoDictionaryKey: "KinkoUpdatePublicKey") as? String).flatMap(UpdateManifest.publicKey(base64:))
    bundleID = bundle.bundleIdentifier
  }

  #if DEBUG
  /// 画面の書き出し用：自動で入れられるものとして描く
  private var pretendsInstallable = false

  init(current: AppVersion?, repository: String?, state: State = .idle, install: Install? = nil) {
    self.current = current
    self.repository = repository.flatMap(Self.validRepository)
    self.state = state
    self.install = install ?? .idle
    pretendsInstallable = install != nil
    publicKey = nil
    bundleID = nil
  }
  #endif

  /// このリリースを自動で入れられるか。入れられなければ理由（手で入れてもらう）
  func automaticInstallBlocker(for release: Release) -> String? {
    #if DEBUG
    if pretendsInstallable { return nil }
    #endif
    guard publicKey != nil, bundleID != nil else { return "この版は自動の入れ替えに対応していません。" }
    guard release.signature != nil else { return "このリリースには署名がないので、自動では入れ替えられません。" }
    do {
      _ = try UpdateInstaller.target()
      return nil
    } catch {
      return error.localizedDescription
    }
  }

  /// 新しい版をダウンロードして確かめる。終われば install が .ready になる
  func startInstall(_ release: Release) {
    guard installTask == nil, let current, let publicKey, let bundleID else { return }
    install = .working("準備しています…", nil)
    installTask = Task {
      defer { installTask = nil }
      do {
        let prepared = try await UpdateInstaller.prepare(
          release, current: current, publicKey: publicKey, target: UpdateInstaller.target(), bundleID: bundleID
        ) { message, fraction in
          await MainActor.run { if case .working = self.install { self.install = .working(message, fraction) } }
        }
        if Task.isCancelled {
          try? FileManager.default.removeItem(at: prepared.work)
          install = .idle
        } else {
          install = .ready(prepared)
        }
      } catch UpdateError.badSignature {
        install = Task.isCancelled ? .idle : .rejected
      } catch {
        install = Task.isCancelled ? .idle : .failed(error.localizedDescription)
      }
    }
  }

  func cancelInstall() {
    installTask?.cancel()
    if case .ready(let prepared) = install { try? FileManager.default.removeItem(at: prepared.work) }
    install = .idle
  }

  /// Kinko を終えて入れ替え、新しい版を開く。入れ替えの処理を動かせなければ、何もせずに理由を出す
  func restartToInstall() {
    guard case .ready(let prepared) = install else { return }
    do {
      try UpdateInstaller.launchSwap(prepared)
      NSApp.terminate(nil)
    } catch {
      install = .failed(UpdateError.cannotInstall(error.localizedDescription).localizedDescription)
    }
  }

  /// "owner/repo" の形で、使える文字だけからなるものを通す（URL に差し込むので）
  private static func validRepository(_ text: String) -> String? {
    let parts = text.split(separator: "/", omittingEmptySubsequences: false)
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
    guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.unicodeScalars.allSatisfy(allowed.contains) })
    else { return nil }
    return text
  }

  func check() async {
    guard state != .checking else { return }
    guard let repository, let current else {
      state = .failed("確認先のリポジトリか、この版の番号が分かりません。")
      return
    }
    state = .checking
    cancelInstall()
    do {
      let release = try await Self.fetchLatest(repository: repository, current: current)
      state = release.isNewer(than: current) ? .available(release) : .upToDate(current)
    } catch UpdateError.noRelease {
      // リリースが 1 つもないなら、今の版より新しいものもない
      state = .upToDate(current)
    } catch {
      state = .failed(error.localizedDescription)
    }
  }

  /// クッキーもキャッシュも残さない接続で、最新のリリースを取る
  private static func fetchLatest(repository: String, current: AppVersion) async throws -> Release {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 15
    configuration.httpCookieStorage = nil
    configuration.urlCache = nil
    let session = URLSession(configuration: configuration)
    defer { session.finishTasksAndInvalidate() }

    var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("Kinko/\(current)", forHTTPHeaderField: "User-Agent")
    let data: Data, response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw UpdateError.network(error.localizedDescription)
    }
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    if status == 404 { throw UpdateError.noRelease }
    guard status == 200 else { throw UpdateError.network("HTTP \(status)") }
    // リリースの情報はふつう数 KB。大きすぎる答えは読まない
    guard data.count <= 1_000_000 else { throw UpdateError.unreadable }
    return try Release.decode(data)
  }
}
