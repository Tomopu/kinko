import Testing

@testable import KinkoCore

@Test func cellAddressesRoundTrip() {
  #expect(CellAddress("A1") == CellAddress(row: 0, column: 0))
  #expect(CellAddress("aa10") == CellAddress(row: 9, column: 26))
  #expect(CellAddress("XFD1048576")?.description == "XFD1048576")
  for bad in ["", "A", "1", "A0", "XFE1", "A1048577", "A01", "あ1"] {
    #expect(CellAddress(bad) == nil, "\(bad)")
  }
}

@Test func literalsFollowExcelRules() {
  #expect(CellInput.literal("120") == .number(120))
  #expect(CellInput.literal("50%") == .number(0.5))
  #expect(CellInput.literal("true") == .bool(true))
  #expect(CellInput.literal("'120") == .text("120"))
  #expect(CellInput.literal("nan") == .text("nan"))
  #expect(CellInput.literal("#N/A") == .error(.na))
  #expect(CellInput.text("120") == "'120")
  #expect(CellInput.text("=1") == "'=1")
  #expect(CellInput.text("りんご") == "りんご")
  #expect(CellInput.number(3) == "3")
  #expect(CellInput.number(0.1) == "0.1")
}

@Test func relativeReferencesShift() {
  #expect(Formula.shifted("=A1+$B$1+$C1+D$1", rowOffset: 2, columnOffset: 1) == "=B3+$B$1+$C3+E$1")
  #expect(Formula.shifted("=SUM(A1:B2)*2", rowOffset: 1, columnOffset: 0) == "=SUM(A2:B3)*2")
  #expect(Formula.shifted("=SUM(A:A)", rowOffset: 5, columnOffset: 1) == "=SUM(B:B)")
  // 表の外へ出る参照は #REF!
  #expect(Formula.shifted("=A1", rowOffset: -1, columnOffset: 0) == "=#REF!")
}

@Test func shiftingKeepsTheRestOfTheText() {
  #expect(Formula.shifted(#"=IF(A1 > 0, "A1です", 'シート 2'!B2)"#, rowOffset: 1, columnOffset: 0)
    == #"=IF(A2 > 0, "A1です", 'シート 2'!B3)"#)
  #expect(Formula.shifted("=売上!A1+LOG10(A1)", rowOffset: 1, columnOffset: 0) == "=売上!A2+LOG10(A2)")
}

@Test func lexerTellsFunctionsFromReferences() throws {
  let references = Formula.references(in: "=SUM(A1:B2)+LOG10(C3)+Sheet2!$D$4")
  #expect(references.map(\.text) == ["A1:B2", "C3", "Sheet2!$D$4"])
}

@Test func sheetNamesAreQuotedWhenNeeded() {
  #expect(FormulaReference.quotedSheetName("Sheet1") == "Sheet1")
  #expect(FormulaReference.quotedSheetName("売上") == "売上")
  #expect(FormulaReference.quotedSheetName("My Sheet") == "'My Sheet'")
  #expect(FormulaReference.quotedSheetName("A1") == "'A1'")
  #expect(FormulaReference.quotedSheetName("it's") == "'it''s'")
}
