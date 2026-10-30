import Foundation

/// 箇条書き・番号付きリスト・チェックリストの行で Return を押したときの動き（Obsidian と同じ）
public enum ListContinuation: Equatable, Sendable {
  /// リストの行ではない。普通に改行する
  case none
  /// 改行して、次の行の頭にこの文字列を入れる（例：「- [ ] 」「3. 」）
  case continueWith(String)
  /// 中身のない項目で Return を押した。行頭の記号（この長さ）を消してリストを終える
  case endList(markerLength: Int)
}

public enum MarkdownLists {
  /// 行頭の空白・記号（- * + や 1. 2)）・空白・チェック欄
  private static let pattern = try! NSRegularExpression(pattern: #"^([ \t]*)(?:([-*+])|(\d{1,9})([.)]))([ \t]+)(\[[ xX]\][ \t]+)?"#)

  /// 行頭で「[ ]」や「[]」のあとに空白を打ったら、チェックリストの「- [ ] 」に置き換える（Notion と同じ近道）。
  /// linePrefix は行頭からカーソルまで（打った空白は含まない）。置き換えないときは nil
  public static func checkboxShortcut(linePrefix: String, typed: String) -> String? {
    guard typed == " " else { return nil }
    let indent = linePrefix.prefix { $0 == " " || $0 == "\t" }
    let rest = linePrefix.dropFirst(indent.count)
    return rest == "[ ]" || rest == "[]" ? indent + "- [ ] " : nil
  }

  /// line はカーソルのある行の、行頭からカーソルまでの文字列
  public static func continuation(for line: String) -> ListContinuation {
    let nsLine = line as NSString
    guard let match = pattern.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) else {
      return .none
    }
    if match.range.length == nsLine.length {
      return .endList(markerLength: match.range.length)
    }
    func group(_ index: Int) -> String? {
      let range = match.range(at: index)
      return range.location == NSNotFound ? nil : nsLine.substring(with: range)
    }
    let indent = group(1) ?? ""
    let spacing = group(5) ?? " "
    let marker: String
    if let bullet = group(2) {
      marker = bullet
    } else {
      // 番号は 1 つ進める。桁が大きすぎて数にできないときは、そのまま続ける
      let number = group(3).flatMap { Int($0) }.map { String($0 + 1) } ?? (group(3) ?? "1")
      marker = number + (group(4) ?? ".")
    }
    // チェック済みの項目の次も、未チェックの項目にする
    let checkbox = group(6) == nil ? "" : "[ ] "
    return .continueWith(indent + marker + spacing + checkbox)
  }
}
