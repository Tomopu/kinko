import Foundation
import Testing

@testable import KinkoCore

@Suite("数式の計算")
struct CalculatorTests {
  /// cells を並べた表の Z99 に formula を入れて計算する
  private func calculate(_ formula: String, _ cells: [String: String] = [:]) -> CellValue {
    var sheet = Sheet(cells: cells)
    sheet["Z99"] = formula
    return Calculator(workbook: Workbook(sheets: [sheet])).value(sheet: 0, at: address("Z99"))
  }

  @Test("演算子は Excel と同じ優先順位で計算する", arguments: [
    ("=1+2*3", CellValue.number(7)),
    ("=(1+2)*3", .number(9)),
    // 符号は ^ より先、^ は左から
    ("=-2^2", .number(4)),
    ("=2^3^2", .number(64)),
    ("=50%*10", .number(5)),
    // & は + より後
    (#"="a"&1+1"#, .text("a2")),
  ])
  func arithmeticFollowsExcelPrecedence(formula: String, expected: CellValue) {
    // Given / When
    let value = calculate(formula)

    // Then
    #expect(value == expected)
  }

  @Test("計算結果は有効数字 15 桁で見せる")
  func resultsShowFifteenDigits() {
    // Given / When
    let value = calculate("=0.1+0.2")

    // Then
    #expect(value.displayText == "0.3")
  }

  @Test("計算できないときはエラーを値として返す", arguments: [
    ("=1/0", CellValue.error(.div0)),
    (#"="x"+1"#, .error(.value)),
    ("=NOPE(1)", .error(.name)),
    ("=1+", .error(.name)),
    ("=SQRT(-1)", .error(.num)),
    // IFERROR はエラーを別の値に替える
    (#"=IFERROR(1/0, "ゼロ")"#, .text("ゼロ")),
  ])
  func errorsAreValues(formula: String, expected: CellValue) {
    // Given / When
    let value = calculate(formula)

    // Then
    #expect(value == expected)
  }

  @Test("参照先のエラーはそのまま伝わる")
  func errorsPropagate() {
    // Given / When
    let value = calculate("=A1+1", ["A1": "=1/0"])

    // Then
    #expect(value == .error(.div0))
  }

  @Test("参照と範囲の値を使って計算する", arguments: [
    ("=A1+A2", CellValue.number(3)),
    ("=B1+1", .number(11)),
    // 集計は数だけを数える（COUNTA は文字列も）
    ("=SUM(A1:A4)", .number(6)),
    ("=SUM(A:A)", .number(6)),
    ("=AVERAGE(A1:A3)", .number(2)),
    ("=COUNT(A1:A4)", .number(3)),
    ("=COUNTA(A1:A4)", .number(4)),
    ("=MAX(A1:A3, 10)", .number(10)),
    // 空のセルは 0
    ("=C1", .number(0)),
    ("=C1+1", .number(1)),
  ])
  func referencesAndRanges(formula: String, expected: CellValue) {
    // Given: A1〜A3 に 1〜3、A4 に文字列、B1 に A1 を使う数式
    let cells = ["A1": "1", "A2": "2", "A3": "3", "A4": "りんご", "B1": "=A1*10"]

    // When
    let value = calculate(formula, cells)

    // Then
    #expect(value == expected)
  }

  @Test("循環参照は止めて #CIRC! にする")
  func circularReferencesStop() {
    // Given: A1 と B1 が互いを指す
    let sheet = Sheet(cells: ["A1": "=B1", "B1": "=A1"])

    // When
    let value = Calculator(workbook: Workbook(sheets: [sheet])).value(sheet: 0, at: address("A1"))

    // Then
    #expect(value == .error(.circular))
  }

  @Test("下へ長く続く参照の連鎖でも、スタックがあふれずに計算できる")
  func longChainsDoNotOverflow() {
    // Given: A1 が 1 で、A2 から A5000 は 1 つ上に 1 を足す
    var sheet = Sheet(cells: ["A1": "1"])
    for row in 2...5000 { sheet["A\(row)"] = "=A\(row - 1)+1" }

    // When
    let values = Calculator(workbook: Workbook(sheets: [sheet])).values(sheet: 0)

    // Then
    #expect(values[address("A5000")] == .number(5000))
  }

  @Test("別のシートを参照でき、ないシートへの参照は #REF!")
  func otherSheets() {
    // Given
    let first = Sheet(cells: ["A1": "='売上 表'!A1*2", "A2": "=Nope!A1"])
    let second = Sheet(name: "売上 表", cells: ["A1": "42"])

    // When
    let calculator = Calculator(workbook: Workbook(sheets: [first, second]))

    // Then
    #expect(calculator.value(sheet: 0, at: address("A1")) == .number(84))
    #expect(calculator.value(sheet: 0, at: address("A2")) == .error(.ref))
  }

  @Test("論理の関数と比較", arguments: [
    (#"=IF(A1>=60, "合格", "不合格")"#, ["A1": "75"], CellValue.text("合格")),
    // 偽のときの値がなければ FALSE
    (#"=IF(A1>=60, "合格")"#, ["A1": "10"], .bool(false)),
    ("=AND(TRUE, 1, A1)", ["A1": "0"], .bool(false)),
    ("=OR(FALSE, 1)", [:], .bool(true)),
    // 文字列の比較は大文字小文字を区別しない
    (#"="abc"="ABC""#, [:], .bool(true)),
  ])
  func logicFunctions(formula: String, cells: [String: String], expected: CellValue) {
    // Given / When
    let value = calculate(formula, cells)

    // Then
    #expect(value == expected)
  }

  @Test("文字列の関数は日本語も 1 文字ずつ扱う", arguments: [
    (#"=CONCAT(A1:A2, "!")"#, ["A1": "こん", "A2": "にちは"], CellValue.text("こんにちは!")),
    (#"=LEFT("金庫アプリ", 2)&MID("金庫アプリ", 3, 2)&RIGHT("金庫アプリ")"#, [:], .text("金庫アプリ")),
    (#"=LEN("日本語")"#, [:], .number(3)),
    // 前後の空白を除き、間の空白は 1 つにする
    (#"=TRIM("  a   b ")"#, [:], .text("a b")),
  ])
  func textFunctions(formula: String, cells: [String: String], expected: CellValue) {
    // Given / When
    let value = calculate(formula, cells)

    // Then
    #expect(value == expected)
  }

  @Test("丸めは Excel と同じ結果にする", arguments: [
    // 2 進の誤差に左右されず、0 から遠い方へ四捨五入する
    ("=ROUND(2.675, 2)", CellValue.number(2.68)),
    ("=ROUND(-2.5, 0)", .number(-3)),
    ("=ROUNDDOWN(1234.5678, -2)", .number(1200)),
    ("=ROUNDUP(1.21, 1)", .number(1.3)),
    // MOD は割る数と同じ符号、INT は小さい方へ
    ("=MOD(-3, 2)", .number(1)),
    ("=INT(-1.5)", .number(-2)),
  ])
  func roundingMatchesExcel(formula: String, expected: CellValue) {
    // Given / When
    let value = calculate(formula)

    // Then
    #expect(value == expected)
  }

  @Test("条件付きの集計", arguments: [
    (#"=SUMIF(A1:A4, "りんご", B1:B4)"#, CellValue.number(400)),
    // * は任意の文字列
    (#"=COUNTIF(A1:A4, "り*")"#, .number(2)),
    (#"=COUNTIF(B1:B4, ">=200")"#, .number(3)),
    // "" は空のセル（空の入力の A4 と、何も入れていない A5）
    (#"=COUNTIF(A1:A5, "")"#, .number(2)),
    (#"=AVERAGEIF(B1:B4, "<>100")"#, .number(300)),
  ])
  func conditionalFunctions(formula: String, expected: CellValue) {
    // Given: A 列に果物（A4 は空）、B 列に値段
    let cells = [
      "A1": "りんご", "A2": "みかん", "A3": "りんご", "A4": "",
      "B1": "100", "B2": "200", "B3": "300", "B4": "400",
    ]

    // When
    let value = calculate(formula, cells)

    // Then
    #expect(value == expected)
  }

  @Test("VLOOKUP は近似一致と完全一致で探す", arguments: [
    // 近似一致はそれ以下でいちばん大きい値の行
    ("=VLOOKUP(72, A1:B3, 2)", CellValue.text("C")),
    ("=VLOOKUP(80, A1:B3, 2, FALSE)", .text("A")),
    ("=VLOOKUP(81, A1:B3, 2, FALSE)", .error(.na)),
    // ひらがなとカタカナは別の文字
    (#"=VLOOKUP("リンゴ", D1:E1, 2, FALSE)"#, .error(.na)),
    (#"=VLOOKUP("りんご", D1:E1, 2, FALSE)"#, .number(120)),
    // 範囲の外の列は #REF!
    ("=VLOOKUP(1, A1:B3, 3)", .error(.ref)),
  ])
  func vlookup(formula: String, expected: CellValue) {
    // Given: A〜B 列に点数と評価、D1:E1 に品名と値段
    let cells = ["A1": "0", "B1": "D", "A2": "60", "B2": "C", "A3": "80", "B3": "A", "D1": "りんご", "E1": "120"]

    // When
    let value = calculate(formula, cells)

    // Then
    #expect(value == expected)
  }

  @Test("TODAY() は今日の日付を文字列で返す")
  func todayIsADateText() {
    // Given: 今日が 2026 年 10 月 30 日
    let sheet = Sheet(cells: ["A1": "=TODAY()"])
    let today = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 12))!

    // When
    let value = Calculator(workbook: Workbook(sheets: [sheet]), today: today).value(sheet: 0, at: address("A1"))

    // Then
    #expect(value == .text("2026/10/30"))
  }
}
