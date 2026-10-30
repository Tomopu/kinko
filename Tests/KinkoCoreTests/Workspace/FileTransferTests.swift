import Foundation
import Testing

@testable import KinkoCore

@Suite("ファイルの取り込みと書き出し")
struct FileTransferTests {
  /// Windows で使われる Shift_JIS（CP932）のバイト列
  private static func cp932(_ text: String) -> Data {
    text.data(using: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue))))!
  }

  @Test("文字のファイルは、よく使われる文字コードのどれでも読める", arguments: [
    ("a.md", Data("# 見出し".utf8), "# 見出し"),
    // BOM 付きの UTF-8 は BOM を取り除く
    ("bom.txt", Data([0xEF, 0xBB, 0xBF]) + Data("本文".utf8), "本文"),
    ("sjis.txt", cp932("日本語"), "日本語"),
  ])
  func textFilesImportInCommonEncodings(name: String, data: Data, expected: String) throws {
    // Given / When
    let item = try FileTransfer.importFile(named: name, data: data)

    // Then
    #expect(item.text == expected)
  }

  @Test("中身がバイナリのファイルや、古い .xls 形式は取り込まない")
  func binaryFilesAreRefused() {
    // Given / When / Then
    #expect(throws: FileTransferError.binary("image.png")) {
      try FileTransfer.importFile(named: "image.png", data: Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x01]))
    }
    #expect(throws: (any Error).self) {
      try FileTransfer.importFile(named: "old.xls", data: Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]))
    }
  }

  @Test("CSV はファイル名を名前にしたシート 1 枚の表として取り込む")
  func spreadsheetsBecomeSheets() throws {
    // Given / When
    let csv = try FileTransfer.importFile(named: "売上.csv", data: Data("品名,数\nりんご,3\n".utf8))

    // Then
    #expect(csv.isSheet)
    #expect(csv.sheet?.sheets[0].name == "売上")
    #expect(csv.sheet?.sheets[0]["B2"] == "3")
  }

  @Test("表を .xlsx で書き出して読み戻すと入力（数式を含む）が同じに戻り、CSV には計算した値を書く")
  func sheetsRoundTripThroughXLSX() throws {
    // Given
    let sheet = Sheet(name: "家計", cells: ["A1": "1200", "A2": "=A1*2", "B1": "'007"])
    let item = WorkspaceItem.sheet("家計簿", workbook: Workbook(sheets: [sheet]))

    // When
    let back = try FileTransfer.importFile(named: "家計簿.xlsx", data: FileTransfer.exportData(for: item))
    let csv = String(decoding: try FileTransfer.exportData(for: item, as: "x.csv"), as: UTF8.self)

    // Then
    #expect(FileTransfer.exportName(for: item) == "家計簿.xlsx")
    #expect(back.sheet == item.sheet)
    #expect(csv.contains("1200,007") && csv.contains("2400"))
  }

  @Test("フォルダは中身ごと書き出して取り込め、同じ場所へもう一度書き出しても上書きしない")
  func foldersExportAndImportAsTrees() throws {
    // Given: 書類/メモ.md と 書類/表/予算 の木
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let tree = WorkspaceItem.folder("書類", children: [
      .file("メモ.md", text: "本文"),
      .folder("表", children: [.sheet("予算")]),
    ])
    let target = directory.appendingPathComponent("書類")

    // When: 書き出す
    try FileTransfer.export(tree, to: target)

    // Then: 表は .xlsx になり、2 回目は失敗する
    #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("表/予算.xlsx").path))
    #expect(throws: (any Error).self) { try FileTransfer.export(tree, to: target) }

    // When: 取り込む
    let imported = try FileTransfer.importItem(at: target)

    // Then
    #expect(imported.name == "書類")
    #expect(imported.children?.map(\.name).sorted() == ["メモ.md", "表"])
    #expect(imported.children?.first { $0.name == "表" }?.children?.first?.isSheet == true)
  }
}
