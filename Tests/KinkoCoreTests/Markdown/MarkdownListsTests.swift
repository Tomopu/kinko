import Testing

@testable import KinkoCore

@Test func bulletsContinue() {
  #expect(MarkdownLists.continuation(for: "- りんご") == .continueWith("- "))
  #expect(MarkdownLists.continuation(for: "  * 字下げ") == .continueWith("  * "))
  #expect(MarkdownLists.continuation(for: "+ プラス") == .continueWith("+ "))
}

@Test func numbersCountUp() {
  #expect(MarkdownLists.continuation(for: "1. 一つ目") == .continueWith("2. "))
  #expect(MarkdownLists.continuation(for: "9) 九つ目") == .continueWith("10) "))
}

/// チェック済みの次も未チェックの項目になる
@Test func checklistsContinueUnchecked() {
  #expect(MarkdownLists.continuation(for: "- [ ] 買い物") == .continueWith("- [ ] "))
  #expect(MarkdownLists.continuation(for: "- [x] 済んだ") == .continueWith("- [ ] "))
  #expect(MarkdownLists.continuation(for: "  - [X] 字下げ") == .continueWith("  - [ ] "))
  #expect(MarkdownLists.continuation(for: "1. [ ] 番号つき") == .continueWith("2. [ ] "))
}

/// 中身のない項目で Return を押すと、記号を消してリストを終える
@Test func emptyItemEndsList() {
  #expect(MarkdownLists.continuation(for: "- ") == .endList(markerLength: 2))
  #expect(MarkdownLists.continuation(for: "- [ ] ") == .endList(markerLength: 6))
  #expect(MarkdownLists.continuation(for: "  3. ") == .endList(markerLength: 5))
}

@Test func otherLinesAreNotLists() {
  for line in ["", "ふつうの文", "-ハイフンだけ", "2026-10-30", "**太字**", "[ ] 記号なしのチェック欄"] {
    #expect(MarkdownLists.continuation(for: line) == .none, "\(line)")
  }
}

@Test func bracketShortcutBecomesChecklist() {
  #expect(MarkdownLists.checkboxShortcut(linePrefix: "[ ]", typed: " ") == "- [ ] ")
  #expect(MarkdownLists.checkboxShortcut(linePrefix: "[]", typed: " ") == "- [ ] ")
  #expect(MarkdownLists.checkboxShortcut(linePrefix: "  []", typed: " ") == "  - [ ] ")
  #expect(MarkdownLists.checkboxShortcut(linePrefix: "[]", typed: "a") == nil)
  #expect(MarkdownLists.checkboxShortcut(linePrefix: "文 []", typed: " ") == nil)
  #expect(MarkdownLists.checkboxShortcut(linePrefix: "- [ ]", typed: " ") == nil)
}
