import Foundation
import Testing

@testable import KinkoCore

private func bold() -> CellStyle {
  var style = CellStyle()
  style.bold = true
  return style
}

@Test func numberFormatsShowNumbers() {
  #expect(NumberFormat.general.format(1234.5) == nil)
  #expect(NumberFormat.number(decimals: 0, grouping: true).format(1234567.8) == "1,234,568")
  #expect(NumberFormat.number(decimals: 2, grouping: true).format(-1234.5) == "-1,234.50")
  #expect(NumberFormat.number(decimals: 2, grouping: false).format(2.675) == "2.68")
  #expect(NumberFormat.currency(decimals: 0).format(-1500) == "-¥1,500")
  #expect(NumberFormat.currency(decimals: 0).format(-0.2) == "¥0")
  #expect(NumberFormat.percent(decimals: 1).format(0.125) == "12.5%")
  #expect(NumberFormat.number(decimals: 0, grouping: false).format(-0.4) == "0")
  #expect(NumberFormat.general.withDecimals(2) == .number(decimals: 2, grouping: false))
  #expect(NumberFormat.percent(decimals: 1).withDecimals(-1) == .percent(decimals: 0))
}

@Test func colorsParseHex() {
  #expect(CellColor(hex: "#FF8000") == CellColor(red: 255, green: 128, blue: 0))
  #expect(CellColor(hex: "FF1E90FF")?.description == "1E90FF")
  #expect(CellColor(hex: "red") == nil)
}

@Test func stylesSurviveJSONAndDefaultsDisappear() throws {
  var style = CellStyle()
  style.bold = true
  style.fillColor = CellColor(hex: "FFF2CC")
  style.alignment = .center
  style.numberFormat = .currency(decimals: 0)
  style.borders = CellBorders(top: BorderLine(style: .double, color: CellColor(hex: "C00000")), bottom: .thin)
  var sheet = Sheet(name: "S")
  sheet[style: CellAddress("B2")!] = style
  sheet[style: CellAddress("C3")!] = CellStyle()
  #expect(sheet.styles.count == 1)
  let decoded = try JSONDecoder().decode(Sheet.self, from: JSONEncoder().encode(sheet))
  #expect(decoded == sheet)
  // 既定の値は JSON に書かない
  let json = String(decoding: try JSONEncoder().encode(CellStyle()), as: UTF8.self)
  #expect(json == "{}")
}

@Test func stylesMoveWithRowsAndColumns() {
  var sheet = Sheet(name: "S")
  sheet[CellAddress("A2")!] = "x"
  sheet[style: CellAddress("A2")!] = bold()
  var book = Workbook(sheets: [sheet])
  book.insertRows(at: 0, count: 2, inSheet: 0)
  #expect(book.sheets[0][style: CellAddress("A4")!].bold)
  #expect(!book.sheets[0][style: CellAddress("A2")!].bold)
  book.deleteRows(3...3, inSheet: 0)
  #expect(book.sheets[0].styles.isEmpty)
}

@Test func fillCopiesStyles() {
  var sheet = Sheet(name: "S")
  sheet[CellAddress("A1")!] = "1"
  sheet[style: CellAddress("A1")!] = bold()
  sheet.fill(from: CellRange(CellAddress("A1")!), direction: .down, count: 2, incrementsSingleNumbers: true)
  #expect(sheet[CellAddress("A3")!] == "3")
  #expect(sheet[style: CellAddress("A3")!].bold)
}

@Test func sortingMovesWholeRows() {
  var sheet = Sheet(name: "S")
  let rows = [["みかん", "300"], ["りんご", "100"], ["", "50"], ["バナナ", "200"]]
  for (r, row) in rows.enumerated() {
    for (c, input) in row.enumerated() { sheet[CellAddress(row: r, column: c)] = input }
    sheet[CellAddress(row: r, column: 2)] = "=B\(r + 1)*2"
  }
  sheet[style: CellAddress("A2")!] = bold()
  var book = Workbook(sheets: [sheet])
  let range = CellRange(CellAddress("A1")!, CellAddress("C4")!)
  book.sortRows(range, by: 1, ascending: true, inSheet: 0)
  let sorted = book.sheets[0]
  #expect((0..<4).map { sorted[CellAddress(row: $0, column: 1)] } == ["50", "100", "200", "300"])
  #expect(sorted[CellAddress("A2")!] == "りんご")
  #expect(sorted[style: CellAddress("A2")!].bold)
  // 数式は動いた先の行を指す
  #expect(sorted[CellAddress("C1")!] == "=B1*2")

  // 空のセルは降順でも最後
  book.sortRows(range, by: 0, ascending: false, inSheet: 0)
  #expect((0..<4).map { book.sheets[0][CellAddress(row: $0, column: 0)] } == ["りんご", "みかん", "バナナ", ""])
}

@Test func rowHeightsMoveWithRowsAndSurviveJSON() throws {
  var sheet = Sheet(name: "S")
  sheet.rowHeights = [2: 40]
  var wrapped = CellStyle()
  wrapped.wraps = true
  wrapped.verticalAlignment = .top
  sheet[style: CellAddress("A3")!] = wrapped
  sheet[CellAddress("A3")!] = "1 行目\n2 行目"
  var book = Workbook(sheets: [sheet])
  book.insertRows(at: 0, count: 1, inSheet: 0)
  #expect(book.sheets[0].rowHeights == [3: 40])
  book.deleteRows(3...3, inSheet: 0)
  #expect(book.sheets[0].rowHeights.isEmpty)
  // セルだけをずらすときは、行の高さは動かない
  book.sheets[0].rowHeights = [5: 30]
  book.insertCells(CellRange(CellAddress("A1")!), shift: .vertical, inSheet: 0)
  #expect(book.sheets[0].rowHeights == [5: 30])

  let decoded = try JSONDecoder().decode(Sheet.self, from: JSONEncoder().encode(sheet))
  #expect(decoded == sheet)
  #expect(String(decoding: try JSONEncoder().encode(sheet), as: UTF8.self).contains(#""rowHeights":{"3":40}"#))
}

/// 形式 4 までの金庫の罫線（細い実線の辺を数で持っていた）も読める
@Test func legacyBordersBecomeThinLines() throws {
  let style = try JSONDecoder().decode(CellStyle.self, from: Data(#"{"borders":5}"#.utf8))
  #expect(style.borders == CellBorders(top: .thin, bottom: .thin))
  var lines = CellBorders()
  lines[.left] = BorderLine(style: .dashDot, color: CellColor(hex: "0070C0"))
  #expect(try JSONDecoder().decode(CellBorders.self, from: JSONEncoder().encode(lines)) == lines)
}
