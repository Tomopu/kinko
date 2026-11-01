import Foundation

/// アプリの版（"0.13.0" や "v0.13"）。数を「.」で区切って順に比べ、足りない桁は 0 とみなす（0.13 と 0.13.0 は同じ）
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
  public let parts: [Int]

  /// 先頭の "v" は無視する。"-beta" のような後ろの印は比べない。数で始まらないものは nil
  public init?(_ text: String) {
    var text = Substring(text.trimmingCharacters(in: .whitespaces))
    if text.first == "v" || text.first == "V" { text = text.dropFirst() }
    let core = text.prefix { $0.isNumber || $0 == "." }
    let parts = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
    guard !parts.isEmpty, parts.count <= 4, !parts.contains(nil) else { return nil }
    self.parts = parts.map { $0! }
  }

  public var description: String { parts.map(String.init).joined(separator: ".") }

  public static func < (a: AppVersion, b: AppVersion) -> Bool {
    for index in 0..<max(a.parts.count, b.parts.count) {
      let x = index < a.parts.count ? a.parts[index] : 0
      let y = index < b.parts.count ? b.parts[index] : 0
      if x != y { return x < y }
    }
    return false
  }

  public static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }
}

/// GitHub のリリース（/repos/{owner}/{repo}/releases/latest の答え）のうち、使うところだけ。
/// 外から来るデータなので、開いてよい URL（github.com の https）だけを受け付け、説明文の長さも切り詰める
public struct Release: Equatable, Sendable {
  public var version: AppVersion
  public var title: String
  /// 変更内容。Markdown のまま（画面ではただの文字として見せる）
  public var notes: String
  /// リリースのページ
  public var page: URL
  /// 添付された DMG。なければ nil（リリースのページから手で選んでもらう）
  public var dmg: URL?
  /// DMG の書き付け（`<DMG の名前>.sig`、UpdateManifest）。なければ自動では入れず、手で入れてもらう
  public var signature: URL?

  public static let maxNotesLength = 4_000

  public init(version: AppVersion, title: String, notes: String, page: URL, dmg: URL?, signature: URL? = nil) {
    self.version = version
    self.title = title
    self.notes = notes
    self.page = page
    self.dmg = dmg
    self.signature = dmg == nil ? nil : signature
  }

  private struct Payload: Decodable {
    var tag_name: String
    var name: String?
    var body: String?
    var html_url: String
    var draft: Bool?
    var prerelease: Bool?
    var assets: [Asset]?

    struct Asset: Decodable {
      var name: String
      var browser_download_url: String
    }
  }

  /// GitHub の答えを読む。下書き・プレリリース・版として読めないタグ・github.com 以外を指す URL は断る
  public static func decode(_ data: Data) throws -> Release {
    let payload: Payload
    do {
      payload = try JSONDecoder().decode(Payload.self, from: data)
    } catch {
      throw UpdateError.unreadable
    }
    guard payload.draft != true, payload.prerelease != true, let version = AppVersion(payload.tag_name) else {
      throw UpdateError.unreadable
    }
    guard let page = githubURL(payload.html_url) else { throw UpdateError.unreadable }
    let dmgAsset = payload.assets?.first { $0.name.lowercased().hasSuffix(".dmg") }
    let dmg = dmgAsset.flatMap { githubURL($0.browser_download_url) }
    let signature = dmgAsset.flatMap { asset in
      payload.assets?.first { $0.name.lowercased() == asset.name.lowercased() + ".sig" }
    }.flatMap { githubURL($0.browser_download_url) }
    var notes = (payload.body ?? "").replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    if notes.count > maxNotesLength { notes = String(notes.prefix(maxNotesLength)) + "…" }
    let title = (payload.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return Release(version: version, title: title.isEmpty ? payload.tag_name : String(title.prefix(200)), notes: notes, page: page, dmg: dmg, signature: signature)
  }

  /// https で github.com を指す URL だけを通す（ほかのサイトへ誘導されないように）
  private static func githubURL(_ text: String) -> URL? {
    guard let url = URL(string: text), url.scheme == "https", url.host?.lowercased() == "github.com" else { return nil }
    return url
  }

  /// 今の版と比べた結果
  public func isNewer(than current: AppVersion) -> Bool { version > current }
}

public enum UpdateError: Error, Equatable, LocalizedError {
  /// リポジトリはあるが、リリースがまだない（またはリポジトリがない）
  case noRelease
  case unreadable
  case network(String)
  /// 書き付けの署名が合わない、または書き付けとダウンロードした DMG が合わない
  case badSignature
  /// 自動では入れ替えられない（理由つき）。DMG を手で入れてもらう
  case cannotInstall(String)

  public var errorDescription: String? {
    switch self {
    case .noRelease: "公開されているリリースが見つかりませんでした。"
    case .unreadable: "リリースの情報を読めませんでした。"
    case .network(let reason): "インターネットにつながっているか確かめてください。（\(reason)）"
    case .badSignature: "ダウンロードしたものが、配布元の署名と合いませんでした。安全のため入れ替えません。"
    case .cannotInstall(let reason): "自動では入れ替えられませんでした。\(reason)"
    }
  }
}
