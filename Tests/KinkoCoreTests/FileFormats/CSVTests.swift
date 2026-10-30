import Foundation
import Testing

@testable import KinkoCore

private func cells(_ sheet: Sheet) -> [String: String] {
  Dictionary(uniqueKeysWithValues: sheet.cells.map { ($0.key.description, $0.value) })
}

@Test func csvReadsQuotedFields() throws {
  let text = "名前,金額,メモ\r\n\"山田, 太郎\",120,\"1行目\n2行目\"\r\n\"引用符\"\"の中\",TRUE,\r\n,,x\n短い行\n"
  let sheet = try CSV.read(Data(text.utf8), name: "読込")
  #expect(sheet.name == "読込")
  #expect(
    cells(sheet) == [
      "A1": "名前", "B1": "金額", "C1": "メモ",
      "A2": "山田, 太郎", "B2": "120", "C2": "1行目\n2行目",
      "A3": "引用符\"の中", "B3": "TRUE",
      "C4": "x",
      "A5": "短い行",
    ])
  // 数や真偽値に見える項目は、そのまま入力として入れる（Kinko が数や TRUE として扱う）
  #expect(CellInput.literal(sheet[CellAddress("B2")!]) == .number(120))
}

@Test func csvLineEndings() throws {
  // CR だけ・LF だけ・CRLF、最後の改行なし、引用の中の CRLF
  let sheet = try CSV.read(Data("a\rb\nc\r\n\"d\r\ne\"".utf8), name: "S")
  #expect(cells(sheet) == ["A1": "a", "A2": "b", "A3": "c", "A4": "d\r\ne"])
  // 空の行は空の行として残る
  #expect(cells(try CSV.read(Data("a\n\nb\n".utf8), name: "S")) == ["A1": "a", "A3": "b"])
  #expect(try CSV.read(Data(), name: "S").cells.isEmpty)
}

@Test func csvDoesNotEvaluateFormulas() throws {
  let sheet = try CSV.read(Data("=1+1,'abc,\"=HYPERLINK(\"\"http://example.com\"\")\"\n".utf8), name: "S")
  #expect(cells(sheet) == ["A1": "'=1+1", "B1": "''abc", "C1": "'=HYPERLINK(\"http://example.com\")"])
  #expect(CellInput.isFormula(sheet[CellAddress("A1")!]) == false)
  #expect(CellInput.literal(sheet[CellAddress("A1")!]) == .text("=1+1"))
}

@Test func csvEncodings() throws {
  // BOM 付き UTF-8
  #expect(cells(try CSV.read(Data([0xEF, 0xBB, 0xBF]) + Data("日本語,1".utf8), name: "S")) == ["A1": "日本語", "B1": "1"])
  // CP932（Shift_JIS）の "日本語,①"（① は CP932 にだけある文字）
  let cp932 = Data([0x93, 0xFA, 0x96, 0x7B, 0x8C, 0xEA, 0x2C, 0x87, 0x40])
  #expect(cells(try CSV.read(cp932, name: "S")) == ["A1": "日本語", "B1": "①"])
  // BOM 付き UTF-16（リトルエンディアン）とタブ区切り
  let utf16 = Data([0xFF, 0xFE]) + "名前\t値\r\n".data(using: .utf16LittleEndian)!
  #expect(cells(try CSV.read(utf16, name: "S", separator: "\t")) == ["A1": "名前", "B1": "値"])
}

@Test func csvLimits() throws {
  let wide = String(repeating: ",", count: CellAddress.maxColumns) + "x"
  #expect(throws: SpreadsheetFileError.tooManyColumns(limit: CellAddress.maxColumns)) {
    try CSV.read(Data(wide.utf8), name: "S")
  }
  let tall = String(repeating: "\n", count: CellAddress.maxRows) + "x"
  #expect(throws: SpreadsheetFileError.tooManyRows(limit: CellAddress.maxRows)) {
    try CSV.read(Data(tall.utf8), name: "S")
  }
  let row = String(repeating: "1,", count: 1000) + "1\n"
  let many = String(repeating: row, count: SpreadsheetLimits.maxCells / 1001 + 1)
  #expect(throws: SpreadsheetFileError.tooManyCells(limit: SpreadsheetLimits.maxCells)) {
    try CSV.read(Data(many.utf8), name: "S")
  }
}

@Test func csvWrite() throws {
  var sheet = Sheet(name: "S")
  sheet[CellAddress("A1")!] = "a,b"
  sheet[CellAddress("B1")!] = "say \"hi\""
  sheet[CellAddress("C1")!] = "1行目\n2行目"
  sheet[CellAddress("A2")!] = "=1+1"
  sheet[CellAddress("C3")!] = " 空白 "
  let data = CSV.write(sheet) { address in
    address == CellAddress("A2")! ? .number(2) : CellInput.literal(sheet[address])
  }
  #expect(data.starts(with: [0xEF, 0xBB, 0xBF]))
  #expect(
    String(decoding: data.dropFirst(3), as: UTF8.self)
      == "\"a,b\",\"say \"\"hi\"\"\",\"1行目\n2行目\"\r\n2,,\r\n,, 空白 \r\n")
  // タブ区切りなら , は囲まない
  let tsv = CSV.write(sheet, values: { CellInput.literal(sheet[$0]) }, separator: "\t")
  #expect(String(decoding: tsv.dropFirst(3), as: UTF8.self).hasPrefix("a,b\t\"say \"\"hi\"\"\"\t"))
  // 書いたものを読み戻せる（数式は計算結果の値になる）
  let back = try CSV.read(data, name: "S")
  #expect(cells(back) == ["A1": "a,b", "B1": "say \"hi\"", "C1": "1行目\n2行目", "A2": "2", "C3": " 空白 "])
  #expect(CSV.write(Sheet(name: "空"), values: { _ in .empty }) == Data([0xEF, 0xBB, 0xBF]))
}
