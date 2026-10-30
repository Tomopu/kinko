import Testing

@testable import KinkoCore

@Suite("行・列・セル・シートの挿入と削除")
struct SheetEditTests {
  /// cells を並べた Sheet1 と、その後ろに others を続けたブック
  private func workbook(_ cells: [String: String], _ others: [Sheet] = []) -> Workbook {
    Workbook(sheets: [Sheet(cells: cells)] + others)
  }

  @Test("行を挿入するとセルと参照がずれ、間に挿入した範囲は広がる")
  func insertingRows() {
    // Given
    var book = workbook(["A1": "1", "A2": "2", "A3": "=SUM(A1:A2)", "B1": "=A2*$A$2"])

    // When: 2 行目に 1 行挿入する
    book.insertRows(at: 1, count: 1, inSheet: 0)

    // Then
    let sheet = book.sheets[0]
    #expect(sheet["A1"] == "1")
    #expect(sheet["A2"] == "")
    #expect(sheet["A3"] == "2")
    #expect(sheet["A4"] == "=SUM(A1:A3)")
    #expect(sheet["B1"] == "=A3*$A$3")
  }

  @Test("行を削除すると範囲は縮み、消した行を直接指していた参照は #REF! になる")
  func deletingRows() {
    // Given
    var book = workbook(["A1": "1", "A2": "2", "A3": "3", "A4": "=SUM(A1:A3)", "B1": "=A2", "B2": "=A3"])

    // When: 2 行目を削除する
    book.deleteRows(1...1, inSheet: 0)

    // Then: 消した行にあった B2 の数式は行ごと消える
    let sheet = book.sheets[0]
    #expect(sheet["A2"] == "3")
    #expect(sheet["A3"] == "=SUM(A1:A2)")
    #expect(sheet["B1"] == "=#REF!")
    #expect(sheet["B2"] == "")
    #expect(Calculator(workbook: book).value(sheet: 0, at: address("A3")) == .number(4))
  }

  @Test("範囲をまるごと削除すると #REF! になる")
  func deletingTheWholeRange() {
    // Given
    var book = workbook(["C1": "=SUM(A2:A3)"])

    // When: 2〜3 行目を削除する
    book.deleteRows(1...2, inSheet: 0)

    // Then
    #expect(book.sheets[0]["C1"] == "=SUM(#REF!)")
  }

  @Test("列を挿入するとセル・参照・列の幅がずれる")
  func insertingColumns() {
    // Given: B 列の幅が 150
    var book = workbook(["A1": "1", "B1": "2", "C1": "=A1+B1"])
    book.sheets[0].columnWidths = [1: 150]

    // When: B 列に 2 列挿入する
    book.insertColumns(at: 1, count: 2, inSheet: 0)

    // Then
    let sheet = book.sheets[0]
    #expect(sheet["D1"] == "2")
    #expect(sheet["E1"] == "=A1+D1")
    #expect(sheet.columnWidths == [3: 150])
  }

  @Test("列を削除すると、消した列への参照は #REF! になり、ほかの参照はずれる")
  func deletingColumns() {
    // Given
    var book = workbook(["A1": "1", "D1": "2", "E1": "=A1+D1"])

    // When: A 列を削除する
    book.deleteColumns(0...0, inSheet: 0)

    // Then
    #expect(book.sheets[0]["D1"] == "=#REF!+C1")
  }

  @Test("別のシートからの参照は動き、そのシート自身への参照は動かない")
  func otherSheetsFollow() {
    // Given: 集計シートから Sheet1!A2 と自分の A2 を指す
    var other = Sheet(name: "集計")
    other["A1"] = "=Sheet1!A2+A2"
    var book = workbook(["A2": "5"], [other])

    // When: Sheet1 の先頭に 1 行挿入する
    book.insertRows(at: 0, count: 1, inSheet: 0)

    // Then
    #expect(book.sheets[1]["A1"] == "=Sheet1!A3+A2")
  }

  @Test("セルを挿入すると、その列の下だけがずれる")
  func insertingCells() {
    // Given
    var book = workbook(["A1": "a", "A2": "b", "B1": "x", "C1": "=A1&A2&B1"])

    // When: A1 にセルを挿入して下へずらす
    book.insertCells(range("A1"), shift: .vertical, inSheet: 0)

    // Then
    let sheet = book.sheets[0]
    #expect(sheet["A1"] == "")
    #expect(sheet["A2"] == "a")
    #expect(sheet["A3"] == "b")
    #expect(sheet["B1"] == "x")
    #expect(sheet["C1"] == "=A2&A3&B1")
  }

  @Test("セルを削除すると、その行の右だけが左へ詰まる")
  func deletingCells() {
    // Given
    var book = workbook(["A2": "a", "A3": "b", "B1": "x", "C1": "=A2&A3&B1"])

    // When: A1 を削除して左へ詰める
    book.deleteCells(range("A1"), shift: .horizontal, inSheet: 0)

    // Then
    let sheet = book.sheets[0]
    #expect(sheet["A1"] == "x")
    #expect(sheet["B1"] == "=A2&A3&A1")
  }

  @Test("シートの名前を変えると、大文字小文字を問わずそのシートへの参照を書き換え、必要なら引用符で囲む")
  func renamingSheets() throws {
    // Given
    var book = workbook(["A1": "=Data!A1*2", "A2": "=data!A1"], [Sheet(name: "Data", cells: ["A1": "1"])])

    // When
    try book.renameSheet(1, to: "売上 2026")

    // Then
    let sheet = book.sheets[0]
    #expect(sheet["A1"] == "='売上 2026'!A1*2")
    #expect(sheet["A2"] == "='売上 2026'!A1")
  }

  @Test("使えない文字や、大文字小文字を問わず重なる名前には変えられない")
  func renamingRejectsBadNames() {
    // Given
    var book = workbook([:], [Sheet(name: "Data")])

    // When / Then
    #expect(throws: WorkspaceError.invalidSheetName) { try book.renameSheet(1, to: "a/b") }
    #expect(throws: WorkspaceError.duplicateName("sheet1")) { try book.renameSheet(1, to: "sheet1") }
  }

  @Test("シートを削除すると、そのシートへの参照は #REF! になる")
  func removingSheets() {
    // Given
    var book = workbook(["A1": "=Data!A1*2"], [Sheet(name: "Data", cells: ["A1": "1"])])

    // When
    book.removeSheet(1)

    // Then
    #expect(book.sheets.count == 1)
    #expect(book.sheets[0]["A1"] == "=#REF!*2")
  }

  @Test("最後の 1 枚のシートは削除できない")
  func keepingTheLastSheet() {
    // Given
    var book = workbook([:])

    // When
    book.removeSheet(0)

    // Then
    #expect(book.sheets.count == 1)
  }
}
