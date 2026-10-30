import Foundation
import Markdown

/// Markdown の装飾 1 つ分。エディタはこれを見て文字に見た目を付ける
public struct MarkdownSpan: Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    case heading(level: Int)
    case strong
    case emphasis
    case strikethrough
    case inlineCode
    case codeBlock
    case blockQuote
    case link
    /// 箇条書きの「-」「*」「+」。中黒（•）に置き換えて見せる
    case bullet
    /// タスクのチェック欄「[ ]」「[x]」。☐ ☑ として見せる
    case taskBox(checked: Bool)
    /// チェック済みのタスク（- [x]）の本文
    case doneTask
    case thematicBreak
    case table
  }

  public var kind: Kind
  /// 装飾がかかる範囲（記号も含む）。NSString と同じ UTF-16 単位
  public var range: NSRange
  /// 記法の記号（#、**、` など）。カーソルがその行にないときは隠す
  public var markers: [NSRange]
}

public enum MarkdownSpans {
  public static func parse(_ text: String) -> [MarkdownSpan] {
    var walker = SpanWalker(source: SourceText(text))
    walker.visit(Document(parsing: text))
    return walker.spans
  }
}

/// swift-markdown の位置（行と、行頭からの UTF-8 バイト数）を、NSString の位置（UTF-16 単位）に直す。
/// 日本語は UTF-8 で 3 バイト、UTF-16 で 1 単位なので、ここを取り違えると装飾がずれる
struct SourceText {
  let string: NSString
  private let utf16OffsetAtUTF8: [Int]
  private let lineStartUTF8: [Int]

  init(_ text: String) {
    string = text as NSString
    var offsets: [Int] = []
    var lineStarts = [0]
    offsets.reserveCapacity(text.utf8.count + 1)
    var utf8 = 0
    var utf16 = 0
    for scalar in text.unicodeScalars {
      let width = UTF8.width(scalar)
      for _ in 0..<width { offsets.append(utf16) }
      utf8 += width
      utf16 += UTF16.width(scalar)
      if scalar == "\n" { lineStarts.append(utf8) }
    }
    offsets.append(utf16)
    utf16OffsetAtUTF8 = offsets
    lineStartUTF8 = lineStarts
  }

  func offset(_ location: SourceLocation) -> Int {
    let line = min(max(location.line - 1, 0), lineStartUTF8.count - 1)
    let utf8 = min(lineStartUTF8[line] + location.column - 1, utf16OffsetAtUTF8.count - 1)
    return utf16OffsetAtUTF8[max(utf8, 0)]
  }

  func range(_ sourceRange: SourceRange?) -> NSRange? {
    guard let sourceRange else { return nil }
    let start = offset(sourceRange.lowerBound)
    let end = offset(sourceRange.upperBound)
    return end > start ? NSRange(location: start, length: end - start) : nil
  }

  /// range の先頭から、characters に含まれる文字が続く長さ
  func leadingRun(in range: NSRange, of characters: String) -> Int {
    var count = 0
    while count < range.length,
      let scalar = Unicode.Scalar(string.character(at: range.location + count)),
      characters.unicodeScalars.contains(scalar)
    {
      count += 1
    }
    return count
  }
}

private struct SpanWalker: MarkupWalker {
  let source: SourceText
  var spans: [MarkdownSpan] = []

  mutating func visitHeading(_ heading: Heading) {
    if let range = source.range(heading.range) {
      // 「## 」のような行頭の記号（後ろの空白まで）。下線式の見出し（=== や ---）は記号を隠さない
      let hashes = source.leadingRun(in: range, of: "#")
      let marker = hashes > 0 ? hashes + source.leadingRun(in: NSRange(location: range.location + hashes, length: range.length - hashes), of: " \t") : 0
      spans.append(MarkdownSpan(
        kind: .heading(level: heading.level), range: range,
        markers: marker > 0 ? [NSRange(location: range.location, length: marker)] : []))
    }
    descendInto(heading)
  }

  mutating func visitStrong(_ strong: Strong) {
    addDelimited(strong, kind: .strong, characters: "*_", maximum: 2)
    descendInto(strong)
  }

  mutating func visitEmphasis(_ emphasis: Emphasis) {
    addDelimited(emphasis, kind: .emphasis, characters: "*_", maximum: 1)
    descendInto(emphasis)
  }

  mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
    addDelimited(strikethrough, kind: .strikethrough, characters: "~", maximum: 2)
    descendInto(strikethrough)
  }

  mutating func visitInlineCode(_ inlineCode: InlineCode) {
    addDelimited(inlineCode, kind: .inlineCode, characters: "`", maximum: .max)
  }

  mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
    guard let range = source.range(codeBlock.range) else { return }
    var markers: [NSRange] = []
    // 「```」で囲んだブロックなら、最初と最後の行（囲みの行）を記号として扱う
    let first = source.string.lineRange(for: NSRange(location: range.location, length: 0))
    if isFence(first) {
      markers.append(withoutNewline(NSIntersectionRange(first, range)))
      let last = source.string.lineRange(for: NSRange(location: NSMaxRange(range) - 1, length: 0))
      if last.location > first.location, isFence(last) {
        markers.append(withoutNewline(NSIntersectionRange(last, range)))
      }
    }
    spans.append(MarkdownSpan(kind: .codeBlock, range: range, markers: markers.filter { $0.length > 0 }))
  }

  mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
    if let range = source.range(blockQuote.range) {
      var markers: [NSRange] = []
      let source = source
      source.string.enumerateSubstrings(in: range, options: [.byLines, .substringNotRequired]) { _, line, _, _ in
        let indent = source.leadingRun(in: line, of: " ")
        let start = NSRange(location: line.location + indent, length: line.length - indent)
        if source.leadingRun(in: start, of: ">") == 1 {
          let space = source.leadingRun(in: NSRange(location: start.location + 1, length: start.length - 1), of: " ")
          markers.append(NSRange(location: start.location, length: 1 + min(space, 1)))
        }
      }
      spans.append(MarkdownSpan(kind: .blockQuote, range: range, markers: markers))
    }
    descendInto(blockQuote)
  }

  mutating func visitLink(_ link: Link) {
    if let range = source.range(link.range),
      let first = link.children.first(where: { _ in true }).flatMap({ source.range($0.range) }),
      let last = Array(link.children).last.flatMap({ source.range($0.range) })
    {
      // [本文](URL) の「[」と「](URL)」が記号。<https://…> 形式は本文の前後の 1 文字ずつ
      let textStart = first.location
      let textEnd = NSMaxRange(last)
      var markers: [NSRange] = []
      if textStart > range.location { markers.append(NSRange(location: range.location, length: textStart - range.location)) }
      if NSMaxRange(range) > textEnd { markers.append(NSRange(location: textEnd, length: NSMaxRange(range) - textEnd)) }
      spans.append(MarkdownSpan(kind: .link, range: range, markers: markers))
    }
    descendInto(link)
  }

  mutating func visitListItem(_ listItem: ListItem) {
    if let range = source.range(listItem.range) {
      let bullet = source.leadingRun(in: range, of: "-*+")
      if bullet == 1 {
        spans.append(MarkdownSpan(kind: .bullet, range: NSRange(location: range.location, length: 1), markers: []))
      }
      if let checkbox = listItem.checkbox {
        // 「- 」や「1. 」の後ろにある「[ ]」を探す
        let marker = source.leadingRun(in: range, of: "-*+0123456789.)")
        let afterMarker = NSRange(location: range.location + marker, length: range.length - marker)
        let box = NSRange(location: afterMarker.location + source.leadingRun(in: afterMarker, of: " \t"), length: 3)
        if NSMaxRange(box) <= NSMaxRange(range), source.string.character(at: box.location) == 0x5B {
          spans.append(MarkdownSpan(kind: .taskBox(checked: checkbox == .checked), range: box, markers: []))
          if checkbox == .checked {
            let body = NSRange(location: NSMaxRange(box), length: NSMaxRange(range) - NSMaxRange(box))
            spans.append(MarkdownSpan(kind: .doneTask, range: withoutNewline(body), markers: []))
          }
        }
      }
    }
    descendInto(listItem)
  }

  mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
    if let range = source.range(thematicBreak.range) {
      spans.append(MarkdownSpan(kind: .thematicBreak, range: withoutNewline(range), markers: []))
    }
  }

  mutating func visitTable(_ table: Table) {
    if let range = source.range(table.range) {
      spans.append(MarkdownSpan(kind: .table, range: range, markers: []))
    }
  }

  /// **太字** のように、前後を同じ記号で囲む装飾
  private mutating func addDelimited(_ markup: Markup, kind: MarkdownSpan.Kind, characters: String, maximum: Int) {
    guard let range = source.range(markup.range) else { return }
    let width = min(source.leadingRun(in: range, of: characters), maximum)
    guard width > 0, range.length > width * 2 else { return }
    spans.append(MarkdownSpan(kind: kind, range: range, markers: [
      NSRange(location: range.location, length: width),
      NSRange(location: NSMaxRange(range) - width, length: width),
    ]))
  }

  private func isFence(_ line: NSRange) -> Bool {
    let indent = source.leadingRun(in: line, of: " ")
    let rest = NSRange(location: line.location + indent, length: line.length - indent)
    return source.leadingRun(in: rest, of: "`") >= 3 || source.leadingRun(in: rest, of: "~") >= 3
  }

  private func withoutNewline(_ range: NSRange) -> NSRange {
    var range = range
    while range.length > 0 {
      let last = source.string.character(at: NSMaxRange(range) - 1)
      guard last == 0x0A || last == 0x0D else { break }
      range.length -= 1
    }
    return range
  }
}
