import Testing

@testable import KinkoCore

@Suite("Markdown のリスト入力")
struct MarkdownListsTests {
  @Test("リストの行で Return を押すと次の行に記号を続け、中身のない項目ではリストを終える", arguments: [
    // 箇条書きは同じ記号と字下げで
    ("- りんご", ListContinuation.continueWith("- ")),
    ("  * 字下げ", .continueWith("  * ")),
    ("+ プラス", .continueWith("+ ")),
    // 番号は 1 つ増やす
    ("1. 一つ目", .continueWith("2. ")),
    ("9) 九つ目", .continueWith("10) ")),
    // チェック済みの次も未チェックの項目になる
    ("- [ ] 買い物", .continueWith("- [ ] ")),
    ("- [x] 済んだ", .continueWith("- [ ] ")),
    ("  - [X] 字下げ", .continueWith("  - [ ] ")),
    ("1. [ ] 番号つき", .continueWith("2. [ ] ")),
    // 中身のない項目は、記号（この長さ）を消してリストを終える
    ("- ", .endList(markerLength: 2)),
    ("- [ ] ", .endList(markerLength: 6)),
    ("  3. ", .endList(markerLength: 5)),
    // リストでない行は普通に改行する
    ("", .none),
    ("ふつうの文", .none),
    ("-ハイフンだけ", .none),
    ("2026-10-30", .none),
    ("**太字**", .none),
    ("[ ] 記号なしのチェック欄", .none),
  ])
  func continuation(line: String, expected: ListContinuation) {
    // Given: カーソルまでが line の行
    // When: Return を押す
    let result = MarkdownLists.continuation(for: line)

    // Then
    #expect(result == expected)
  }

  @Test("行頭で「[ ]」や「[]」のあとに空白を打つと、チェックリストの項目に置き換える", arguments: [
    // 置き換える（字下げは保つ）
    ("[ ]", " ", "- [ ] "),
    ("[]", " ", "- [ ] "),
    ("  []", " ", "  - [ ] "),
    // 空白以外を打ったとき・行頭でないとき・すでにチェックリストのときは置き換えない
    ("[]", "a", nil),
    ("文 []", " ", nil),
    ("- [ ]", " ", nil),
  ] as [(String, String, String?)])
  func checkboxShortcut(linePrefix: String, typed: String, expected: String?) {
    // Given / When: linePrefix のあとに typed を打つ
    let result = MarkdownLists.checkboxShortcut(linePrefix: linePrefix, typed: typed)

    // Then
    #expect(result == expected)
  }
}
