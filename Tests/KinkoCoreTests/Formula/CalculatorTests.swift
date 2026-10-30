import Foundation
import Testing

@testable import KinkoCore

/// セルの入力を並べて表を作り、1 つのセルを計算する
private func calculate(_ formula: String, _ cells: [String: String] = [:]) -> CellValue {
  var sheet = Sheet(name: "Sheet1")
  for (key, value) in cells { sheet[CellAddress(key)!] = value }
  sheet[CellAddress("Z99")!] = formula
  return Calculator(workbook: Workbook(sheets: [sheet])).value(sheet: 0, at: CellAddress("Z99")!)
}

@Test func arithmeticFollowsExcelPrecedence() {
  #expect(calculate("=1+2*3") == .number(7))
  #expect(calculate("=(1+2)*3") == .number(9))
  #expect(calculate("=-2^2") == .number(4))
  #expect(calculate("=2^3^2") == .number(64))
  #expect(calculate("=50%*10") == .number(5))
  #expect(calculate("=\"a\"&1+1") == .text("a2"))
  #expect(calculate("=0.1+0.2").displayText == "0.3")
}

@Test func errorsAreValues() {
  #expect(calculate("=1/0") == .error(.div0))
  #expect(calculate("=\"x\"+1") == .error(.value))
  #expect(calculate("=NOPE(1)") == .error(.name))
  #expect(calculate("=1+") == .error(.name))
  #expect(calculate("=SQRT(-1)") == .error(.num))
  #expect(calculate("=IFERROR(1/0, \"ゼロ\")") == .text("ゼロ"))
  #expect(calculate("=A1+1", ["A1": "=1/0"]) == .error(.div0))
}

@Test func referencesAndRanges() {
  let cells = ["A1": "1", "A2": "2", "A3": "3", "A4": "りんご", "B1": "=A1*10"]
  #expect(calculate("=A1+A2", cells) == .number(3))
  #expect(calculate("=SUM(A1:A4)", cells) == .number(6))
  #expect(calculate("=SUM(A:A)", cells) == .number(6))
  #expect(calculate("=AVERAGE(A1:A3)", cells) == .number(2))
  #expect(calculate("=COUNT(A1:A4)", cells) == .number(3))
  #expect(calculate("=COUNTA(A1:A4)", cells) == .number(4))
  #expect(calculate("=MAX(A1:A3, 10)", cells) == .number(10))
  #expect(calculate("=B1+1", cells) == .number(11))
  // 空のセルは 0
  #expect(calculate("=C1", cells) == .number(0))
  #expect(calculate("=C1+1", cells) == .number(1))
}

@Test func circularReferencesStop() {
  var sheet = Sheet(name: "Sheet1")
  sheet[CellAddress("A1")!] = "=B1"
  sheet[CellAddress("B1")!] = "=A1"
  let calculator = Calculator(workbook: Workbook(sheets: [sheet]))
  #expect(calculator.value(sheet: 0, at: CellAddress("A1")!) == .error(.circular))
}

/// 下へ長く続く参照の連鎖でも、上の行から順に計算すればスタックがあふれない
@Test func longChainsDoNotOverflow() {
  var sheet = Sheet(name: "Sheet1")
  sheet[CellAddress(row: 0, column: 0)] = "1"
  for row in 1..<5000 { sheet[CellAddress(row: row, column: 0)] = "=A\(row)+1" }
  let values = Calculator(workbook: Workbook(sheets: [sheet])).values(sheet: 0)
  #expect(values[CellAddress(row: 4999, column: 0)] == .number(5000))
}

@Test func otherSheets() {
  var first = Sheet(name: "Sheet1")
  var second = Sheet(name: "売上 表")
  second[CellAddress("A1")!] = "42"
  first[CellAddress("A1")!] = "='売上 表'!A1*2"
  first[CellAddress("A2")!] = "=Nope!A1"
  let calculator = Calculator(workbook: Workbook(sheets: [first, second]))
  #expect(calculator.value(sheet: 0, at: CellAddress("A1")!) == .number(84))
  #expect(calculator.value(sheet: 0, at: CellAddress("A2")!) == .error(.ref))
}

@Test func logicAndText() {
  #expect(calculate("=IF(A1>=60, \"合格\", \"不合格\")", ["A1": "75"]) == .text("合格"))
  #expect(calculate("=IF(A1>=60, \"合格\")", ["A1": "10"]) == .bool(false))
  #expect(calculate("=AND(TRUE, 1, A1)", ["A1": "0"]) == .bool(false))
  #expect(calculate("=OR(FALSE, 1)") == .bool(true))
  #expect(calculate("=\"abc\"=\"ABC\"") == .bool(true))
  #expect(calculate("=CONCAT(A1:A2, \"!\")", ["A1": "こん", "A2": "にちは"]) == .text("こんにちは!"))
  #expect(calculate("=LEFT(\"金庫アプリ\", 2)&MID(\"金庫アプリ\", 3, 2)&RIGHT(\"金庫アプリ\")") == .text("金庫アプリ"))
  #expect(calculate("=LEN(\"日本語\")") == .number(3))
  #expect(calculate("=TRIM(\"  a   b \")") == .text("a b"))
}

@Test func roundingMatchesExcel() {
  #expect(calculate("=ROUND(2.675, 2)") == .number(2.68))
  #expect(calculate("=ROUND(-2.5, 0)") == .number(-3))
  #expect(calculate("=ROUNDDOWN(1234.5678, -2)") == .number(1200))
  #expect(calculate("=ROUNDUP(1.21, 1)") == .number(1.3))
  #expect(calculate("=MOD(-3, 2)") == .number(1))
  #expect(calculate("=INT(-1.5)") == .number(-2))
}

@Test func conditionalFunctions() {
  let cells = [
    "A1": "りんご", "A2": "みかん", "A3": "りんご", "A4": "",
    "B1": "100", "B2": "200", "B3": "300", "B4": "400",
  ]
  #expect(calculate("=SUMIF(A1:A4, \"りんご\", B1:B4)", cells) == .number(400))
  #expect(calculate("=COUNTIF(A1:A4, \"り*\")", cells) == .number(2))
  #expect(calculate("=COUNTIF(B1:B4, \">=200\")", cells) == .number(3))
  #expect(calculate("=COUNTIF(A1:A5, \"\")", cells) == .number(2))
  #expect(calculate("=AVERAGEIF(B1:B4, \"<>100\")", cells) == .number(300))
}

@Test func vlookupExactAndApproximate() {
  let cells = ["A1": "0", "B1": "D", "A2": "60", "B2": "C", "A3": "80", "B3": "A", "D1": "りんご", "E1": "120"]
  #expect(calculate("=VLOOKUP(72, A1:B3, 2)", cells) == .text("C"))
  #expect(calculate("=VLOOKUP(80, A1:B3, 2, FALSE)", cells) == .text("A"))
  #expect(calculate("=VLOOKUP(81, A1:B3, 2, FALSE)", cells) == .error(.na))
  #expect(calculate("=VLOOKUP(\"リンゴ\", D1:E1, 2, FALSE)", cells) == .error(.na))
  #expect(calculate("=VLOOKUP(\"りんご\", D1:E1, 2, FALSE)", cells) == .number(120))
  #expect(calculate("=VLOOKUP(1, A1:B3, 3)", cells) == .error(.ref))
}

@Test func todayIsADateText() {
  var sheet = Sheet(name: "Sheet1")
  sheet[CellAddress("A1")!] = "=TODAY()"
  let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 12))!
  #expect(Calculator(workbook: Workbook(sheets: [sheet]), today: date).value(sheet: 0, at: CellAddress("A1")!)
    == .text("2026/10/30"))
}
