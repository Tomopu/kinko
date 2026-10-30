import Foundation
import Testing

@testable import KinkoCore

@Test func textFilesImportInCommonEncodings() throws {
  #expect(try FileTransfer.importFile(named: "a.md", data: Data("# 見出し".utf8)).text == "# 見出し")
  #expect(try FileTransfer.importFile(named: "bom.txt", data: Data([0xEF, 0xBB, 0xBF]) + Data("本文".utf8)).text == "本文")
  let cp932 = "日本語".data(using: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue))))!
  #expect(try FileTransfer.importFile(named: "sjis.txt", data: cp932).text == "日本語")
}

@Test func binaryFilesAreRefused() {
  #expect(throws: FileTransferError.binary("image.png")) {
    try FileTransfer.importFile(named: "image.png", data: Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x01]))
  }
}

@Test func spreadsheetsBecomeSheets() throws {
  let csv = try FileTransfer.importFile(named: "売上.csv", data: Data("品名,数\nりんご,3\n".utf8))
  #expect(csv.isSheet)
  #expect(csv.sheet?.sheets[0].name == "売上")
  #expect(csv.sheet?.sheets[0][CellAddress("B2")!] == "3")
  #expect(throws: (any Error).self) { try FileTransfer.importFile(named: "old.xls", data: Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])) }
}

/// 表を .xlsx で書き出して読み戻すと、入力（数式を含む）が同じに戻る
@Test func sheetsRoundTripThroughXLSX() throws {
  var sheet = Sheet(name: "家計")
  sheet[CellAddress("A1")!] = "1200"
  sheet[CellAddress("A2")!] = "=A1*2"
  sheet[CellAddress("B1")!] = "'007"
  let item = WorkspaceItem.sheet("家計簿", workbook: Workbook(sheets: [sheet]))
  #expect(FileTransfer.exportName(for: item) == "家計簿.xlsx")
  let back = try FileTransfer.importFile(named: "家計簿.xlsx", data: FileTransfer.exportData(for: item))
  #expect(back.sheet == item.sheet)
  // CSV は計算した値を書く
  let csv = String(decoding: try FileTransfer.exportData(for: item, as: "x.csv"), as: UTF8.self)
  #expect(csv.contains("1200,007") && csv.contains("2400"))
}

@Test func foldersExportAndImportAsTrees() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let tree = WorkspaceItem.folder("書類", children: [
    .file("メモ.md", text: "本文"),
    .folder("表", children: [.sheet("予算")]),
  ])
  let target = directory.appendingPathComponent("書類")
  try FileTransfer.export(tree, to: target)
  #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("表/予算.xlsx").path))
  // 同じ場所へもう一度書き出しても上書きしない
  #expect(throws: (any Error).self) { try FileTransfer.export(tree, to: target) }

  let imported = try FileTransfer.importItem(at: target)
  #expect(imported.name == "書類")
  #expect(imported.children?.map(\.name).sorted() == ["メモ.md", "表"])
  #expect(imported.children?.first { $0.name == "表" }?.children?.first?.isSheet == true)
}
