import Foundation
import Testing

@testable import KinkoCore

/// 範囲が指す文字列を取り出す（どこを装飾するかを、位置の数字ではなく文字で確かめる）
private func text(_ source: String, _ range: NSRange) -> String {
  (source as NSString).substring(with: range)
}

private func spans(_ source: String, _ kind: MarkdownSpan.Kind) -> [MarkdownSpan] {
  MarkdownSpans.parse(source).filter { $0.kind == kind }
}

@Test func headingMarkersIncludeTrailingSpace() throws {
  let source = "## 見出しです\n本文"
  let heading = try #require(spans(source, .heading(level: 2)).first)
  #expect(text(source, heading.range) == "## 見出しです")
  #expect(heading.markers.map { text(source, $0) } == ["## "])
}

/// 日本語（UTF-8 で 3 バイト）や絵文字（UTF-16 で 2 単位）の後ろでも位置がずれない
@Test func offsetsSurviveMultibyteText() throws {
  let source = "日本語🔑と**太字**と*斜体*と`コード`"
  let strong = try #require(spans(source, .strong).first)
  #expect(text(source, strong.range) == "**太字**")
  #expect(strong.markers.map { text(source, $0) } == ["**", "**"])
  let emphasis = try #require(spans(source, .emphasis).first)
  #expect(text(source, emphasis.range) == "*斜体*")
  let code = try #require(spans(source, .inlineCode).first)
  #expect(text(source, code.range) == "`コード`")
  #expect(code.markers.map { text(source, $0) } == ["`", "`"])
}

@Test func offsetsOnLaterLines() throws {
  let source = "一行目\n二行目の ~~取り消し~~ です"
  let strike = try #require(spans(source, .strikethrough).first)
  #expect(text(source, strike.range) == "~~取り消し~~")
  #expect(strike.markers.map { text(source, $0) } == ["~~", "~~"])
}

@Test func linkHidesBracketsAndURL() throws {
  let source = "詳しくは[公式サイト](https://example.com)へ"
  let link = try #require(spans(source, .link).first)
  #expect(text(source, link.range) == "[公式サイト](https://example.com)")
  #expect(link.markers.map { text(source, $0) } == ["[", "](https://example.com)"])
}

@Test func fencedCodeBlockMarksFenceLines() throws {
  let source = "前\n```swift\nlet a = 1\n```\n後"
  let block = try #require(spans(source, .codeBlock).first)
  #expect(block.markers.map { text(source, $0) } == ["```swift", "```"])
  #expect(text(source, block.range).contains("let a = 1"))
}

@Test func blockQuoteMarksEachLine() throws {
  let source = "> 一行目\n> 二行目"
  let quote = try #require(spans(source, .blockQuote).first)
  #expect(quote.markers.map { text(source, $0) } == ["> ", "> "])
}

@Test func bulletsAndTasks() throws {
  let source = "- りんご\n* みかん\n1. 番号つき\n- [x] 済んだこと\n- [ ] まだのこと"
  let bullets = spans(source, .bullet)
  #expect(bullets.map { text(source, $0.range) } == ["-", "*", "-", "-"])
  let done = spans(source, .doneTask)
  #expect(done.map { text(source, $0.range) } == [" 済んだこと"])
  #expect(spans(source, .taskBox(checked: true)).map { text(source, $0.range) } == ["[x]"])
  #expect(spans(source, .taskBox(checked: false)).map { text(source, $0.range) } == ["[ ]"])
}

@Test func plainTextHasNoSpans() {
  #expect(MarkdownSpans.parse("ただの文章です。\n2 * 3 = 6").isEmpty)
  #expect(MarkdownSpans.parse("").isEmpty)
}
