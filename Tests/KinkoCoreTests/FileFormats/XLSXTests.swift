import Foundation
import Testing

@testable import KinkoCore

/// Excel の出力をまねて Python 標準の zipfile で作った .xlsx（Kinko の ZIP 実装とは独立した実装で作ったもの）。
/// 共有文字列（書式付きの文字列・ふりがな）、日付（組み込み 14 番とユーザー定義 "yyyy年m月d日"）、日付でない "0.00"、
/// 共有数式、配列数式、データテーブル、インライン文字列、真偽値、エラー、r 属性のないセルと行、グラフシート、2 枚目のシート、列の幅を含む
private let excelSample = """
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
UEsFBgAAAAAIAAgACAIAADQNAAAAAA==
"""

@Test func readsExcelLikeWorkbook() throws {
  let data = try #require(Data(base64Encoded: excelSample, options: .ignoreUnknownCharacters))
  let workbook = try XLSX.read(data)
  let master = "=A2*2"
  let expected = Workbook(sheets: [
    Sheet(
      name: "売上",
      cells: [
        "A1": "名前", "B1": "太字 と普通", "C1": "東京", "D1": "山田太郎",
        // 1900 年の閏年の誤り: 60 は架空の 2/29、59 以前は 1 日ずれる
        "E1": "1900/02/28", "F1": "1900/02/29", "G1": "1900/03/01", "H1": "1900/01/01",
        "A2": "120", "B2": master, "C2": "2026/10/30", "D2": "2026/10/30",
        "A3": "1.5", "B3": Formula.shifted(master, rowOffset: 1, columnOffset: 0), "C3": "TRUE", "D3": "#N/A",
        "A4": "インライン", "B4": Formula.shifted(master, rowOffset: 2, columnOffset: 0), "C4": "'123", "D4": "12:00",
        "E4": "2026/10/30 18:00",
        "A5": "1234.5", "B5": #"=CONCAT(A1,"_xlfn.x")"#, "C5": "改行\r\nあり & <記号>", "D5": "=SUM(A2:A3*2)", "E5": "7",
      ].reduce(into: [:]) { $0[CellAddress($1.key)!] = $1.value },
      // 12.625 文字 → 93 ポイント、20 文字 → 145 ポイント。I 列から XFD 列までの指定は使わない
      columnWidths: [0: 93, 2: 145, 3: 145],
      // "0.00" と "#,##0.00_);[Red]\(#,##0.00\)" は日付ではなく、数の表示形式
      styles: [
        CellAddress("A3")!: style { $0.numberFormat = .number(decimals: 2, grouping: false) },
        CellAddress("A5")!: style { $0.numberFormat = .number(decimals: 2, grouping: true) },
      ]),
    Sheet(name: "Sheet2", cells: [CellAddress("A1")!: "名前", CellAddress("B3")!: "3.14159"]),
  ])
  #expect(workbook == expected)
}

@Test func rejectsNonXLSXFiles() throws {
  let ole = Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1] + [UInt8](repeating: 0, count: 504))
  #expect(throws: SpreadsheetFileError.legacyExcel) { try XLSX.read(ole) }
  let encrypted = ole + Data("EncryptedPackage".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
  #expect(throws: SpreadsheetFileError.encryptedExcel) { try XLSX.read(encrypted) }
  #expect(throws: SpreadsheetFileError.notXLSX) { try XLSX.read(Data("a,b,c\n".utf8)) }
  #expect(throws: SpreadsheetFileError.notXLSX) { try XLSX.read(ZipWriter.archive([("readme.txt", Data("hi".utf8))])) }
  // 共有文字列の番号が範囲外
  #expect(throws: SpreadsheetFileError.invalidPart("xl/worksheets/sheet1.xml")) {
    try XLSX.read(package(sheetXML: #"<row r="1"><c r="A1" t="s"><v>5</v></c></row>"#))
  }
  // Excel の範囲外の位置
  #expect(throws: SpreadsheetFileError.invalidPart("xl/worksheets/sheet1.xml")) {
    try XLSX.read(package(sheetXML: #"<row r="1"><c r="XFE1"><v>1</v></c></row>"#))
  }
  #expect(throws: SpreadsheetFileError.invalidPart("xl/worksheets/sheet1.xml")) {
    try XLSX.read(package(sheetXML: #"<row r="1"><c r="A1"><v>1</v></row>"#))
  }
}

@Test func rejectsDTD() throws {
  // Billion Laughs: 展開すると 10 億個の "lol" になる
  var dtd = #"<!DOCTYPE worksheet [<!ENTITY lol "lol">"#
  dtd += #"<!ENTITY lol1 "&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;">"#
  for level in 2...9 { dtd += "<!ENTITY lol\(level) \"" + String(repeating: "&lol\(level - 1);", count: 10) + "\">" }
  dtd += "]>"
  let ns = #"xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main""#
  let bomb = #"<?xml version="1.0"?>\#(dtd)<worksheet \#(ns)><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>&lol9;</t></is></c></row></sheetData></worksheet>"#
  #expect(throws: SpreadsheetFileError.invalidPart("xl/worksheets/sheet1.xml")) {
    try XMLScanner.scan(Data(bomb.utf8), part: "xl/worksheets/sheet1.xml")
  }
  // XXE: 外部のファイルを読ませようとする
  let xxe = #"<?xml version="1.0"?><!DOCTYPE w [<!ENTITY x SYSTEM "file:///etc/passwd">]><w>&x;</w>"#
  #expect(throws: SpreadsheetFileError.invalidPart("p")) { try XMLScanner.scan(Data(xxe.utf8), part: "p") }
  // UTF-16 で書かれていて DOCTYPE の文字列検査をすり抜けても、実体の定義で止まる
  let utf16 = Data([0xFF, 0xFE]) + #"<?xml version="1.0" encoding="UTF-16"?>\#(dtd)<w>&lol9;</w>"#.data(using: .utf16LittleEndian)!
  #expect(throws: SpreadsheetFileError.self) { try XMLScanner.scan(utf16, part: "p") }
}

@Test func writeThenReadRoundTrip() throws {
  var first = Sheet(name: "表1", columnWidths: [0: 120, 2: 64])
  let inputs: [String: String] = [
    "A1": "'123", "A2": "'=1+1", "A3": "日本語", "A4": "=A5*2", "A5": "5",
    "B1": #"=CONCAT(A3,"x")"#, "B2": #"=textjoin(",",TRUE,A1:A3)"#, "B3": "=1/0", "B4": "=A5>1", "B5": "TRUE",
    "C1": "#N/A", "C2": "  前後に空白 ", "C3": "1行目\n2行目\r\n3行目", "C4": "_x000D_ はそのまま", "C5": #"a<b&c"d'"#,
    "D1": #"=" IFS(" & MYCONCAT(1)"#, "D2": "1.5", "D3": "1e+20", "D4": "=NOW()", "D5": "\t",
  ]
  for (key, value) in inputs { first[CellAddress(key)!] = value }
  let workbook = Workbook(sheets: [first, Sheet(name: "Sheet/2*"), Sheet(name: "sheet_2_", cells: [CellAddress(row: 9, column: 27): "x"])])
  let cached: [String: CellValue] = [
    "A4": .number(10), "B1": .text("日本語x"), "B2": .text("123,=1+1,日本語"), "B3": .error(.div0), "B4": .bool(true),
    "D1": .text(" IFS(1"), "D4": .empty,
  ]
  let data = try XLSX.write(workbook) { sheet, address in
    sheet == 0 ? cached[address.description] ?? .empty : .empty
  }

  let read = try XLSX.read(data)
  #expect(read.sheets.map(\.name) == ["表1", "Sheet_2_", "sheet_2_ (2)"])
  #expect(read.sheets[0].cells == first.cells)
  #expect(read.sheets[0].columnWidths == first.columnWidths)
  #expect(read.sheets[1].cells.isEmpty)
  #expect(read.sheets[2].cells == [CellAddress(row: 9, column: 27): "x"])

  // ファイルの中身: キャッシュ値の型と _xlfn. の付け方
  var zip = try ZipArchive(data)
  let xml = String(decoding: try #require(try zip.read("xl/worksheets/sheet1.xml")), as: UTF8.self)
  #expect(xml.contains(#"<c r="A4"><f>A5*2</f><v>10</v></c>"#))
  #expect(xml.contains(#"<c r="B1" t="str"><f>_xlfn.CONCAT(A3,&quot;x&quot;)</f><v>日本語x</v></c>"#))
  #expect(xml.contains(#"<f>_xlfn.textjoin("#))
  #expect(xml.contains(#"<c r="B3" t="e"><f>1/0</f><v>#DIV/0!</v></c>"#))
  #expect(xml.contains(#"<c r="B4" t="b"><f>A5&gt;1</f><v>1</v></c>"#))
  #expect(xml.contains(#"<c r="D1" t="str"><f>&quot; IFS(&quot; &amp; MYCONCAT(1)</f>"#))
  #expect(xml.contains(#"<c r="D4"><f>NOW()</f></c>"#))
  #expect(xml.contains(#"<c r="A1" t="inlineStr"><is><t xml:space="preserve">123</t></is></c>"#))
  #expect(xml.contains(#"<c r="C1" t="e"><v>#N/A</v></c>"#))
  #expect(xml.contains(#"<c r="B5" t="b"><v>1</v></c>"#))
  let workbookXML = String(decoding: try #require(try zip.read("xl/workbook.xml")), as: UTF8.self)
  #expect(workbookXML.contains(#"<calcPr fullCalcOnLoad="1"/>"#))
  #expect(!zip.entries.keys.contains { $0.hasPrefix("docProps") })
}

@Test func functionPrefixes() {
  #expect(XLSX.addFunctionPrefixes(#"IFS(A1>0,"CONCAT(",1)+XLOOKUP(1,A:A,B:B)+'MAXIFS('!A1+SUM(1)"#)
    == #"_xlfn.IFS(A1>0,"CONCAT(",1)+_xlfn.XLOOKUP(1,A:A,B:B)+'MAXIFS('!A1+SUM(1)"#)
  #expect(XLSX.addFunctionPrefixes("SWITCH + SWITCH(1) + _xlfn.SWITCH(2) + A.IFS(3)") == "SWITCH + _xlfn.SWITCH(1) + _xlfn.SWITCH(2) + A.IFS(3)")
  #expect(XLSX.removeFunctionPrefixes(#"_xlfn._xlws.SORT(A1:A3)&"_xlfn.""#) == #"SORT(A1:A3)&"_xlfn.""#)
}

@Test func dateFormats() {
  for code in ["yyyy/m/d", "m月d日", "[$-411]ggge\"年\"m\"月\"d\"日\"", "mmm-yy", "yyyy\"年\"m\"月\"d\"日\";@", "[$-F800]dddd, mmmm dd, yyyy"] {
    #expect(XLSX.dateStyle(formatCode: code) == .date, "\(code)")
  }
  for code in ["h:mm", "mm:ss", "[h]:mm:ss", "h:mm AM/PM", "h\"時\"mm\"分\"", "[mm]"] {
    #expect(XLSX.dateStyle(formatCode: code) == .time, "\(code)")
  }
  for code in ["0.00", "#,##0", "General", "0.00E+00", "[Red]0.00", "\"day\"0", "0\\d", "#,##0_);[Red]\\(#,##0\\)", "@", "0%"] {
    #expect(XLSX.dateStyle(formatCode: code) == nil, "\(code)")
  }
  #expect(XLSX.builtInDateStyle(14) == .date)
  #expect(XLSX.builtInDateStyle(32) == .time)
  #expect(XLSX.builtInDateStyle(2) == nil)

  #expect(XLSX.dateText(serial: 45658, style: .date, date1904: false) == "2025/01/01")
  #expect(XLSX.dateText(serial: 44196, style: .date, date1904: true) == "2025/01/01")
  #expect(XLSX.dateText(serial: 0.75, style: .time, date1904: false) == "18:00")
  #expect(XLSX.dateText(serial: 0.5 + 1.0 / 86_400, style: .time, date1904: false) == "12:00:01")
  #expect(XLSX.dateText(serial: 45658.25, style: .date, date1904: false) == "2025/01/01 06:00")
  #expect(XLSX.dateText(serial: -1, style: .date, date1904: false) == nil)
  // 日付の文字列は数や数式と取り違えられない
  #expect(CellInput.literal("2025/01/01") == .text("2025/01/01"))
  #expect(CellInput.literal("12:00") == .text("12:00"))
}

@Test func sheetNamesFollowExcelRules() {
  #expect(
    XLSX.sheetNames(["a/b", "'引用'", "", "A/B", String(repeating: "長", count: 40), String(repeating: "長", count: 40), "History"])
      == ["a_b", "引用", "Sheet3", "A_B (2)", String(repeating: "長", count: 31), String(repeating: "長", count: 27) + " (2)", "Sheet7"])
}

@Test func escapesTextForXML() {
  #expect(XLSX.escape("a\u{01}b\u{0B}c") == "abc")
  #expect(XLSX.unescapeText("a_x000D__x000a_b_x005F_x0041_") == "a\r\nb_x0041_")
  #expect(XLSX.unescapeText("_xD83D__xDE00_") == "😀")
  #expect(XLSX.unescapeText(XLSX.escapeText("_x0041_").replacingOccurrences(of: "&amp;", with: "&")) == "_x0041_")
}

@Test func rejectsTooManyCells() throws {
  let row = "<row>" + String(repeating: "<c><v>1</v></c>", count: 1000) + "</row>"
  let sheet = String(repeating: row, count: SpreadsheetLimits.maxCells / 1000 + 1)
  #expect(throws: SpreadsheetFileError.tooManyCells(limit: SpreadsheetLimits.maxCells)) {
    try XLSX.read(package(sheetXML: sheet))
  }
}

@Test func readsRawLineFeedsInStrings() throws {
  // Excel は共有文字列・インライン文字列の改行を、そのままの LF で書く
  let data = try package(sheetXML: "<row r=\"1\"><c r=\"A1\" t=\"inlineStr\"><is><t>上\n下</t></is></c></row>")
  #expect(try XLSX.read(data).sheets.first?[CellAddress("A1")!] == "上\n下")
}

/// ほかのブックを参照する式のファイルを作る（共有文字列つき）
private func externalPackage(_ sheetXML: String) throws -> Data {
  let ns = #"xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships""#
  let type = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
  let rels =
    #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#
    + #"<Relationship Id="rId1" Type="\#(type)worksheet" Target="worksheets/sheet1.xml"/>"#
    + #"<Relationship Id="rId2" Type="\#(type)sharedStrings" Target="sharedStrings.xml"/>"#
    + #"<Relationship Id="rId3" Type="\#(type)externalLink" Target="externalLinks/externalLink1.xml"/></Relationships>"#
  return try ZipWriter.archive([
    ("xl/workbook.xml", Data(#"<workbook \#(ns)><sheets><sheet name="S" sheetId="1" r:id="rId1"/></sheets><externalReferences><externalReference r:id="rId3"/></externalReferences></workbook>"#.utf8)),
    ("xl/_rels/workbook.xml.rels", Data(rels.utf8)),
    ("xl/sharedStrings.xml", Data(#"<sst \#(ns)><si><t>東京</t></si></sst>"#.utf8)),
    ("xl/worksheets/sheet1.xml", Data(#"<worksheet \#(ns)><sheetData>\#(sheetXML)</sheetData></worksheet>"#.utf8)),
  ])
}

@Test func externalReferencesBecomeCachedValues() throws {
  let rows = [
    #"<c r="A1" t="s"><f>'[1]売上 2026'!B6</f><v>0</v></c>"#,
    #"<c r="A2"><f>[1]Sheet1!A1*2</f><v>42</v></c>"#,
    #"<c r="A3" t="str"><f>"[1]Sheet1!A1"&amp;"x"</f><v>[1]Sheet1!A1x</v></c>"#,
    #"<c r="A4"><f>SUM([1]!総額)</f></c>"#,
    #"<c r="A5" t="b"><f>'[2]My Sheet'!B2:C3=1</f><v>1</v></c>"#,
    #"<c r="A6"><f>表1[2024]+SUM(表1[[#This Row],[2024]])</f><v>3</v></c>"#,
    #"<c r="A7"><f t="shared" ref="A7:A8" si="0">[1]Sheet1!A1</f><v>5</v></c>"#,
    #"<c r="A8"><f t="shared" si="0"/><v>6</v></c>"#,
    #"<c r="A9" t="e"><f>[1]Sheet1!A1</f><v>#REF!</v></c>"#,
    #"<c r="A10" t="str"><f>[1]Sheet1!A1</f><v>=1+1</v></c>"#,
  ].enumerated().map { #"<row r="\#($0.offset + 1)">\#($0.element)</row>"# }.joined()
  let sheet = try #require(try XLSX.read(externalPackage(rows)).sheets.first)
  let expected: [String: String] = [
    "A1": "東京", "A2": "42", "A3": #"="[1]Sheet1!A1"&"x""#, "A5": "TRUE",
    "A6": "=表1[2024]+SUM(表1[[#This Row],[2024]])", "A7": "5", "A8": "6", "A9": "#REF!",
    // キャッシュ値が "=" で始まる文字列でも、数式としては読まない
    "A10": "'=1+1",
  ]
  #expect(sheet.cells == expected.reduce(into: [:]) { $0[CellAddress($1.key)!] = $1.value })
}

@Test func detectsExternalReferences() {
  for formula in ["=[1]Sheet1!A1", "='[2]My Sheet'!B2:C3", "=SUM([1]!Name)", "=1+[3]売上!A1", "='C:\\dir\\[Book1.xlsx]Sheet1'!A1"] {
    #expect(XLSX.hasExternalReference(formula), "\(formula)")
  }
  for formula in [#"="[1]Sheet1!A1""#, "=表1[2024]", "=表1[[#This Row],[2024]]", "=SUM(表1[[2024]])", "='It''s'!A1", "=A1"] {
    #expect(!XLSX.hasExternalReference(formula), "\(formula)")
  }
}
