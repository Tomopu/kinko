import Foundation
import Testing

@testable import KinkoCore

@Suite("Markdown の装飾の範囲")
struct MarkdownSpansTests {
  /// 範囲が指す文字列を取り出す（どこを装飾するかを、位置の数字ではなく文字で確かめる）
  private func text(_ source: String, _ range: NSRange) -> String {
    (source as NSString).substring(with: range)
  }

  private func spans(_ source: String, _ kind: MarkdownSpan.Kind) -> [MarkdownSpan] {
    MarkdownSpans.parse(source).filter { $0.kind == kind }
  }

  @Test("装飾する範囲と、隠す記号の位置を文字の単位で正しく返す", arguments: [
    // 見出しの記号は後ろの空白まで
    ("## 見出しです\n本文", MarkdownSpan.Kind.heading(level: 2), "## 見出しです", ["## "]),
    // 日本語（UTF-8 で 3 バイト）や絵文字（UTF-16 で 2 単位）の後ろでも位置がずれない
    ("日本語🔑と**太字**と*斜体*と`コード`", .strong, "**太字**", ["**", "**"]),
    ("日本語🔑と**太字**と*斜体*と`コード`", .emphasis, "*斜体*", ["*", "*"]),
    ("日本語🔑と**太字**と*斜体*と`コード`", .inlineCode, "`コード`", ["`", "`"]),
    // 2 行目以降でも位置がずれない
    ("一行目\n二行目の ~~取り消し~~ です", .strikethrough, "~~取り消し~~", ["~~", "~~"]),
    // リンクは括弧と URL を隠す
    ("詳しくは[公式サイト](https://example.com)へ", .link, "[公式サイト](https://example.com)", ["[", "](https://example.com)"]),
  ])
  func rangeAndMarkers(source: String, kind: MarkdownSpan.Kind, expectedRange: String, expectedMarkers: [String]) throws {
    // Given / When
    let span = try #require(spans(source, kind).first)

    // Then
    #expect(text(source, span.range) == expectedRange)
    #expect(span.markers.map { text(source, $0) } == expectedMarkers)
  }

  @Test("コードブロックは囲みの行を記号にし、中身を範囲に含める")
  func fencedCodeBlockMarksFenceLines() throws {
    // Given
    let source = "前\n```swift\nlet a = 1\n```\n後"

    // When
    let block = try #require(spans(source, .codeBlock).first)

    // Then
    #expect(block.markers.map { text(source, $0) } == ["```swift", "```"])
    #expect(text(source, block.range).contains("let a = 1"))
  }

  @Test("引用は行ごとの「> 」を記号にする")
  func blockQuoteMarksEachLine() throws {
    // Given
    let source = "> 一行目\n> 二行目"

    // When
    let quote = try #require(spans(source, .blockQuote).first)

    // Then
    #expect(quote.markers.map { text(source, $0) } == ["> ", "> "])
  }

  @Test("箇条書きの記号とチェック欄を見つけ、済んだタスクの本文に印を付ける")
  func bulletsAndTasks() throws {
    // Given: 箇条書き 2 つ・番号つき・済んだタスク・まだのタスク
    let source = "- りんご\n* みかん\n1. 番号つき\n- [x] 済んだこと\n- [ ] まだのこと"

    // When
    let bullets = spans(source, .bullet)
    let done = spans(source, .doneTask)
    let checked = spans(source, .taskBox(checked: true))
    let unchecked = spans(source, .taskBox(checked: false))

    // Then: 番号は箇条書きの記号に含めない
    #expect(bullets.map { text(source, $0.range) } == ["-", "*", "-", "-"])
    #expect(done.map { text(source, $0.range) } == [" 済んだこと"])
    #expect(checked.map { text(source, $0.range) } == ["[x]"])
    #expect(unchecked.map { text(source, $0.range) } == ["[ ]"])
  }

  @Test("記号のないただの文章（式の * を含む）や空の文字列には装飾がない", arguments: ["ただの文章です。\n2 * 3 = 6", ""])
  func plainTextHasNoSpans(source: String) {
    // Given / When / Then
    #expect(MarkdownSpans.parse(source).isEmpty)
  }
}
