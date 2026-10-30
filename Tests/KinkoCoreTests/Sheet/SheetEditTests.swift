import Testing

@testable import KinkoCore

private func workbook(_ cells: [String: String], _ others: [Sheet] = []) -> Workbook {
  var sheet = Sheet(name: "Sheet1")
  for (key, value) in cells { sheet[CellAddress(key)!] = value }
  return Workbook(sheets: [sheet] + others)
}

private extension Workbook {
  subscript(_ key: String) -> String { sheets[0][CellAddress(key)!] }
}

@Test func insertingRowsMovesCellsAndReferences() {
  var book = workbook(["A1": "1", "A2": "2", "A3": "=SUM(A1:A2)", "B1": "=A2*$A$2"])
  book.insertRows(at: 1, count: 1, inSheet: 0)
  #expect(book["A1"] == "1")
  #expect(book["A2"] == "")
  #expect(book["A3"] == "2")
  // 間に挿入すると範囲が広がる
  #expect(book["A4"] == "=SUM(A1:A3)")
  #expect(book["B1"] == "=A3*$A$3")
}

@Test func deletingRowsShrinksRangesAndBreaksDirectReferences() {
  var book = workbook(["A1": "1", "A2": "2", "A3": "3", "A4": "=SUM(A1:A3)", "B1": "=A2", "B2": "=A3"])
  book.deleteRows(1...1, inSheet: 0)
  #expect(book["A2"] == "3")
  #expect(book["A3"] == "=SUM(A1:A2)")
  // 消した行を直接指していた参照は #REF!
  #expect(book["B1"] == "=#REF!")
  #expect(book["B2"] == "")
  // B2 の数式（=A3）は 1 行上へ動き、A3 は A2 になる
  #expect(book.sheets[0][CellAddress("B1")!] == "=#REF!")
  #expect(Calculator(workbook: book).value(sheet: 0, at: CellAddress("A3")!) == .number(4))
}

@Test func deletingTheWholeRangeIsRefError() {
  var book = workbook(["C1": "=SUM(A2:A3)"])
  book.deleteRows(1...2, inSheet: 0)
  #expect(book["C1"] == "=SUM(#REF!)")
}

@Test func columnsMoveWithWidths() {
  var book = workbook(["A1": "1", "B1": "2", "C1": "=A1+B1"])
  book.sheets[0].columnWidths = [1: 150]
  book.insertColumns(at: 1, count: 2, inSheet: 0)
  #expect(book["D1"] == "2")
  #expect(book["E1"] == "=A1+D1")
  #expect(book.sheets[0].columnWidths == [3: 150])
  book.deleteColumns(0...0, inSheet: 0)
  #expect(book["D1"] == "=#REF!+C1")
}

@Test func otherSheetsFollow() {
  var other = Sheet(name: "集計")
  other[CellAddress("A1")!] = "=Sheet1!A2+A2"
  var book = workbook(["A2": "5"], [other])
  book.insertRows(at: 0, count: 1, inSheet: 0)
  // 別のシートからの参照は動き、そのシート自身への参照は動かない
  #expect(book.sheets[1][CellAddress("A1")!] == "=Sheet1!A3+A2")
}

@Test func insertingCellsShiftsOnlyThatBand() {
  var book = workbook(["A1": "a", "A2": "b", "B1": "x", "C1": "=A1&A2&B1"])
  book.insertCells(CellRange(CellAddress("A1")!), shift: .vertical, inSheet: 0)
  #expect(book["A1"] == "")
  #expect(book["A2"] == "a")
  #expect(book["A3"] == "b")
  #expect(book["B1"] == "x")
  #expect(book["C1"] == "=A2&A3&B1")
  book.deleteCells(CellRange(CellAddress("A1")!), shift: .horizontal, inSheet: 0)
  #expect(book["A1"] == "x")
  #expect(book["B1"] == "=A2&A3&A1")
}

@Test func renamingAndRemovingSheetsRewritesFormulas() throws {
  var other = Sheet(name: "Data")
  other[CellAddress("A1")!] = "1"
  var book = workbook(["A1": "=Data!A1*2", "A2": "=data!A1"], [other])
  try book.renameSheet(1, to: "売上 2026")
  #expect(book["A1"] == "='売上 2026'!A1*2")
  #expect(book["A2"] == "='売上 2026'!A1")
  #expect(throws: WorkspaceError.invalidSheetName) { try book.renameSheet(1, to: "a/b") }
  #expect(throws: WorkspaceError.duplicateName("sheet1")) { try book.renameSheet(1, to: "sheet1") }
  book.removeSheet(1)
  #expect(book["A1"] == "=#REF!*2")
  book.removeSheet(0)
  #expect(book.sheets.count == 1)
}
