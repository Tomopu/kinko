import Testing

@testable import KinkoCore

@Suite("セルの位置・入力・数式の文字列")
struct FormulaTests {
  @Test("A1 形式の位置を行と列の番号に読む（小文字も読む）", arguments: [
    ("A1", 0, 0),
    ("aa10", 9, 26),
  ])
  func cellAddresses(text: String, row: Int, column: Int) {
    // Given / When
    let parsed = CellAddress(text)

    // Then
    #expect(parsed == CellAddress(row: row, column: column))
  }

  @Test("いちばん右下の位置 XFD1048576 は書いたとおりに戻る")
  func lastCellAddressRoundTrips() {
    // Given / When
    let parsed = CellAddress("XFD1048576")

    // Then
    #expect(parsed?.description == "XFD1048576")
  }

  @Test("位置として読めない文字列は nil", arguments: [
    // 列か行が欠けている
    "", "A", "1",
    // 表の外
    "A0", "XFE1", "A1048577",
    // 0 で始まる行番号や、英字でない列名
    "A01", "あ1",
  ])
  func badCellAddresses(text: String) {
    // Given / When
    let parsed = CellAddress(text)

    // Then
    #expect(parsed == nil)
  }

  @Test("数式でない入力は Excel と同じ決まりで値にする", arguments: [
    ("120", CellValue.number(120)),
    ("50%", .number(0.5)),
    ("true", .bool(true)),
    ("#N/A", .error(.na)),
    // ' で始めると数に見えても文字列。nan は数にしない
    ("'120", .text("120")),
    ("nan", .text("nan")),
  ])
  func literals(input: String, expected: CellValue) {
    // Given / When
    let value = CellInput.literal(input)

    // Then
    #expect(value == expected)
  }

  @Test("文字列として入れるときは、数や数式に見えるものだけ ' を付ける", arguments: [
    ("120", "'120"),
    ("=1", "'=1"),
    ("りんご", "りんご"),
  ])
  func textInputs(text: String, expected: String) {
    // Given / When
    let input = CellInput.text(text)

    // Then
    #expect(input == expected)
  }

  @Test("数を入れるときは、元の数に戻るいちばん短い書き方にする", arguments: [
    (3.0, "3"),
    (0.1, "0.1"),
  ])
  func numberInputs(number: Double, expected: String) {
    // Given / When
    let input = CellInput.number(number)

    // Then
    #expect(input == expected)
  }

  @Test("数式をずらすと、相対参照だけが動く", arguments: [
    ("=A1+$B$1+$C1+D$1", 2, 1, "=B3+$B$1+$C3+E$1"),
    ("=SUM(A1:B2)*2", 1, 0, "=SUM(A2:B3)*2"),
    ("=SUM(A:A)", 5, 1, "=SUM(B:B)"),
    // 表の外へ出る参照は #REF!
    ("=A1", -1, 0, "=#REF!"),
  ])
  func relativeReferencesShift(formula: String, rowOffset: Int, columnOffset: Int, expected: String) {
    // Given / When
    let shifted = Formula.shifted(formula, rowOffset: rowOffset, columnOffset: columnOffset)

    // Then
    #expect(shifted == expected)
  }

  @Test("数式をずらしても、文字列・シート名・関数名は書き換えない", arguments: [
    (#"=IF(A1 > 0, "A1です", 'シート 2'!B2)"#, #"=IF(A2 > 0, "A1です", 'シート 2'!B3)"#),
    ("=売上!A1+LOG10(A1)", "=売上!A2+LOG10(A2)"),
  ])
  func shiftingKeepsTheRestOfTheText(formula: String, expected: String) {
    // Given / When: 1 行下へずらす
    let shifted = Formula.shifted(formula, rowOffset: 1, columnOffset: 0)

    // Then
    #expect(shifted == expected)
  }

  @Test("参照を拾うとき、LOG10 のような関数名は参照と取り違えない")
  func lexerTellsFunctionsFromReferences() {
    // Given / When
    let references = Formula.references(in: "=SUM(A1:B2)+LOG10(C3)+Sheet2!$D$4")

    // Then
    #expect(references.map(\.text) == ["A1:B2", "C3", "Sheet2!$D$4"])
  }

  @Test("シート名は参照と紛らわしいときや空白・' を含むときだけ ' で囲む", arguments: [
    ("Sheet1", "Sheet1"),
    ("売上", "売上"),
    ("My Sheet", "'My Sheet'"),
    ("A1", "'A1'"),
    // 中の ' は 2 つ重ねる
    ("it's", "'it''s'"),
  ])
  func sheetNamesAreQuotedWhenNeeded(name: String, expected: String) {
    // Given / When
    let quoted = FormulaReference.quotedSheetName(name)

    // Then
    #expect(quoted == expected)
  }
}
