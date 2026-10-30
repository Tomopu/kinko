import Foundation
import Testing

@testable import KinkoCore

@Suite("CSV の読み書き")
struct CSVTests {
  /// 書き出しを試すシート。A2 の数式は計算結果 2 として書く
  private let sample = Sheet(
    name: "S",
    cells: ["A1": "a,b", "B1": "say \"hi\"", "C1": "1行目\n2行目", "A2": "=1+1", "C3": " 空白 "])

  private func written(separator: Character = ",") -> Data {
    CSV.write(sample, values: { $0 == address("A2") ? .number(2) : CellInput.literal(sample[$0]) }, separator: separator)
  }

  @Test("引用符で囲んだ項目の中の区切り・改行・二重の引用符を読む")
  func quotedFields() throws {
    // Given
    let text = "名前,金額,メモ\r\n\"山田, 太郎\",120,\"1行目\n2行目\"\r\n\"引用符\"\"の中\",TRUE,\r\n,,x\n短い行\n"

    // When
    let sheet = try CSV.read(Data(text.utf8), name: "読込")

    // Then
    #expect(sheet.name == "読込")
    #expect(
      byA1(sheet.cells) == [
        "A1": "名前", "B1": "金額", "C1": "メモ",
        "A2": "山田, 太郎", "B2": "120", "C2": "1行目\n2行目",
        "A3": "引用符\"の中", "B3": "TRUE",
        "C4": "x",
        "A5": "短い行",
      ])
    // 数や真偽値に見える項目は、そのまま入力として入れる（Kinko が数や TRUE として扱う）
    #expect(CellInput.literal(sheet["B2"]) == .number(120))
  }

  @Test("どの改行でも行を分け、空の行は空の行として残す", arguments: [
    // CR だけ・LF だけ・CRLF、最後の改行なし、引用の中の CRLF
    ("a\rb\nc\r\n\"d\r\ne\"", ["A1": "a", "A2": "b", "A3": "c", "A4": "d\r\ne"]),
    ("a\n\nb\n", ["A1": "a", "A3": "b"]),
    ("", [:]),
  ])
  func lineEndings(text: String, expected: [String: String]) throws {
    // Given / When
    let sheet = try CSV.read(Data(text.utf8), name: "S")

    // Then
    #expect(byA1(sheet.cells) == expected)
  }

  @Test("= で始まる項目は数式にせず、文字列として入れる")
  func formulasStayText() throws {
    // Given
    let text = "=1+1,'abc,\"=HYPERLINK(\"\"http://example.com\"\")\"\n"

    // When
    let sheet = try CSV.read(Data(text.utf8), name: "S")

    // Then
    #expect(byA1(sheet.cells) == ["A1": "'=1+1", "B1": "''abc", "C1": "'=HYPERLINK(\"http://example.com\")"])
    #expect(CellInput.isFormula(sheet["A1"]) == false)
    #expect(CellInput.literal(sheet["A1"]) == .text("=1+1"))
  }

  @Test("文字コードを見分けて読む", arguments: [
    // BOM 付き UTF-8
    (Data([0xEF, 0xBB, 0xBF]) + Data("日本語,1".utf8), ",", ["A1": "日本語", "B1": "1"]),
    // CP932（Shift_JIS）の "日本語,①"（① は CP932 にだけある文字）
    (Data([0x93, 0xFA, 0x96, 0x7B, 0x8C, 0xEA, 0x2C, 0x87, 0x40]), ",", ["A1": "日本語", "B1": "①"]),
    // BOM 付き UTF-16（リトルエンディアン）とタブ区切り
    (Data([0xFF, 0xFE]) + "名前\t値\r\n".data(using: .utf16LittleEndian)!, "\t", ["A1": "名前", "B1": "値"]),
  ] as [(Data, Character, [String: String])])
  func encodings(data: Data, separator: Character, expected: [String: String]) throws {
    // Given / When
    let sheet = try CSV.read(data, name: "S", separator: separator)

    // Then
    #expect(byA1(sheet.cells) == expected)
  }

  @Test("列・行・セルが多すぎるファイルは断る")
  func limits() {
    // Given
    let wide = String(repeating: ",", count: CellAddress.maxColumns) + "x"
    let tall = String(repeating: "\n", count: CellAddress.maxRows) + "x"
    let row = String(repeating: "1,", count: 1000) + "1\n"
    let many = String(repeating: row, count: SpreadsheetLimits.maxCells / 1001 + 1)

    // When / Then
    #expect(throws: SpreadsheetFileError.tooManyColumns(limit: CellAddress.maxColumns)) {
      try CSV.read(Data(wide.utf8), name: "S")
    }
    #expect(throws: SpreadsheetFileError.tooManyRows(limit: CellAddress.maxRows)) {
      try CSV.read(Data(tall.utf8), name: "S")
    }
    #expect(throws: SpreadsheetFileError.tooManyCells(limit: SpreadsheetLimits.maxCells)) {
      try CSV.read(Data(many.utf8), name: "S")
    }
  }

  @Test("BOM 付き UTF-8 で書き、区切り・引用符・改行を含む項目だけを囲む。数式は計算結果を書く")
  func write() {
    // Given / When
    let data = written()

    // Then
    #expect(data.starts(with: [0xEF, 0xBB, 0xBF]))
    #expect(
      String(decoding: data.dropFirst(3), as: UTF8.self)
        == "\"a,b\",\"say \"\"hi\"\"\",\"1行目\n2行目\"\r\n2,,\r\n,, 空白 \r\n")
  }

  @Test("タブ区切りなら , を含む項目は囲まない")
  func writeTabSeparated() {
    // Given / When
    let tsv = CSV.write(sample, values: { CellInput.literal(sample[$0]) }, separator: "\t")

    // Then
    #expect(String(decoding: tsv.dropFirst(3), as: UTF8.self).hasPrefix("a,b\t\"say \"\"hi\"\"\"\t"))
  }

  @Test("書いたものを読み戻せる（数式は計算結果の値になる）")
  func writeThenRead() throws {
    // Given
    let data = written()

    // When
    let back = try CSV.read(data, name: "S")

    // Then
    #expect(byA1(back.cells) == ["A1": "a,b", "B1": "say \"hi\"", "C1": "1行目\n2行目", "A2": "2", "C3": " 空白 "])
  }

  @Test("空のシートは BOM だけを書く")
  func writeEmpty() {
    // Given / When
    let data = CSV.write(Sheet(name: "空"), values: { _ in .empty })

    // Then
    #expect(data == Data([0xEF, 0xBB, 0xBF]))
  }
}
