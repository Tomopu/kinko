import Foundation
import Testing

@testable import KinkoCore

@Suite("アップデートの確認")
struct ReleaseTests {
  /// GitHub の /releases/latest の答えをまねた JSON
  private func payload(
    tag: String = "v0.14.0", name: String? = "Kinko 0.14.0", body: String? = "## 変更\r\n- PDF の検索",
    page: String = "https://github.com/Tomopu/kinko/releases/tag/v0.14.0",
    assets: [(String, String)] = [("Kinko-0.14.0.dmg", "https://github.com/Tomopu/kinko/releases/download/v0.14.0/Kinko-0.14.0.dmg")],
    prerelease: Bool = false
  ) -> Data {
    var object: [String: Any] = [
      "tag_name": tag, "html_url": page, "draft": false, "prerelease": prerelease,
      "assets": assets.map { ["name": $0.0, "browser_download_url": $0.1, "size": 100] },
    ]
    if let name { object["name"] = name }
    if let body { object["body"] = body }
    return try! JSONSerialization.data(withJSONObject: object)
  }

  @Test("版は数として比べ、v や足りない桁は気にしない", arguments: [
    ("0.13.0", "0.14.0", true),
    ("0.9.0", "0.10.0", true),
    ("0.13", "v0.13.0", false),
    ("1.0.0", "0.99.9", false),
    ("0.13.0", "0.13.1-beta", true),
  ])
  func comparesVersions(current: String, latest: String, isNewer: Bool) throws {
    // Given
    let a = try #require(AppVersion(current)), b = try #require(AppVersion(latest))

    // When / Then
    #expect((a < b) == isNewer)
  }

  @Test("数で始まらない版は読まない", arguments: ["", "latest", "v", "1..2", "1.2.3.4.5"])
  func rejectsMalformedVersions(text: String) {
    // Given / When / Then
    #expect(AppVersion(text) == nil)
  }

  @Test("リリースから版・変更内容・DMG を読み、改行は \\n にそろえる")
  func readsRelease() throws {
    // Given / When
    let release = try Release.decode(payload())

    // Then
    #expect(release.version == AppVersion("0.14.0")!)
    #expect(release.title == "Kinko 0.14.0")
    #expect(release.notes == "## 変更\n- PDF の検索")
    #expect(release.dmg?.lastPathComponent == "Kinko-0.14.0.dmg")
    #expect(release.isNewer(than: AppVersion("0.13.0")!))
    #expect(!release.isNewer(than: AppVersion("0.14")!))
  }

  @Test("DMG のないリリースや、github.com 以外を指す DMG は、ページへ案内する")
  func dmgMustBeOnGitHub() throws {
    // Given / When
    let none = try Release.decode(payload(assets: [("source.zip", "https://github.com/x/y/archive/a.zip")]))
    let elsewhere = try Release.decode(payload(assets: [("Kinko.dmg", "https://evil.example.com/Kinko.dmg")]))

    // Then
    #expect(none.dmg == nil)
    #expect(elsewhere.dmg == nil)
  }

  @Test("プレリリース・版として読めないタグ・github.com 以外のページは受け付けない")
  func rejectsUntrustedReleases() {
    // Given / When / Then
    for data in [
      payload(prerelease: true),
      payload(tag: "nightly"),
      payload(page: "http://github.com/Tomopu/kinko/releases/tag/v0.14.0"),
      payload(page: "https://github.com.evil.example/Tomopu/kinko"),
      Data("<html>".utf8),
    ] {
      #expect(throws: UpdateError.unreadable) { try Release.decode(data) }
    }
  }

  @Test("名前のないリリースはタグを名前にし、長すぎる変更内容は切り詰める")
  func fillsTitleAndTrimsNotes() throws {
    // Given / When
    let release = try Release.decode(payload(name: nil, body: String(repeating: "あ", count: Release.maxNotesLength + 10)))

    // Then
    #expect(release.title == "v0.14.0")
    #expect(release.notes.count == Release.maxNotesLength + 1)
  }
}
