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

  private(set) var state = State.idle
  let current: AppVersion?
  /// "owner/repo"。Info.plist の KinkoUpdateRepository で決める
  let repository: String?

  init(bundle: Bundle = .main) {
    current = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
    repository = (bundle.object(forInfoDictionaryKey: "KinkoUpdateRepository") as? String).flatMap(Self.validRepository)
  }

  #if DEBUG
  init(current: AppVersion?, repository: String?, state: State = .idle) {
    self.current = current
    self.repository = repository.flatMap(Self.validRepository)
    self.state = state
  }
  #endif

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
