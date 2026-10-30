import Foundation
import Testing

@testable import KinkoCore

@Suite("ZIP の読み書き")
struct ZipTests {
  /// 中央ディレクトリの最初の項目の位置
  private func centralDirectoryEntry(_ zip: Data) -> Int {
    zip.range(of: Data([0x50, 0x4B, 0x01, 0x02]))!.lowerBound
  }

  private func endOfCentralDirectory(_ zip: Data) -> Int {
    zip.range(of: Data([0x50, 0x4B, 0x05, 0x06]), options: .backwards)!.lowerBound
  }

  /// offset から value をリトルエンディアンで書き換えたもの
  private func patched(_ data: Data, at offset: Int, _ value: some FixedWidthInteger) -> Data {
    var data = data
    for index in 0..<(value.bitWidth / 8) { data[offset + index] = UInt8(truncatingIfNeeded: value >> (8 * index)) }
    return data
  }

  /// 1MB の 0 を 1 つだけ入れた ZIP
  private func bomb() throws -> Data {
    try ZipWriter.archive([("bomb", Data(count: 1_000_000))])
  }

  @Test("CRC-32 は既知の値と一致する", arguments: [
    ("123456789", 0xCBF4_3926 as UInt32),
    ("", 0),
  ])
  func crc32(text: String, expected: UInt32) {
    // Given / When
    let checksum = CRC32.checksum(Array(text.utf8))

    // Then
    #expect(checksum == expected)
  }

  @Test("書いた ZIP を読み戻せる。縮むものだけを圧縮し、日時は固定する")
  func roundTrip() throws {
    // Given: 繰り返しの多い中身・空の中身・乱数
    let repeated = Data(String(repeating: "Kinko の表。", count: 500).utf8)
    let random = Data((0..<300).map { _ in UInt8.random(in: 0...255) })

    // When
    let zip = try ZipWriter.archive([("a.xml", repeated), ("空", Data()), ("フォルダ/乱数.bin", random)])
    var archive = try ZipArchive(zip)

    // Then
    #expect(try archive.read("a.xml") == repeated)
    #expect(try archive.read("空") == Data())
    #expect(try archive.read("フォルダ/乱数.bin") == random)
    #expect(try archive.read("ない") == nil)
    // 繰り返しの多い中身は圧縮され、乱数は縮まないので無圧縮
    #expect(zip.count < repeated.count)
    #expect(archive.entries["フォルダ/乱数.bin"]?.method == 0)
    // 日時は 1980-01-01 00:00 に固定（ローカルヘッダーの 10〜13 バイト目）
    #expect(Array(zip[10..<14]) == [0, 0, 0x21, 0])
  }

  @Test("途中で切れたものや ZIP でないものは断る")
  func truncated() throws {
    // Given
    let zip = try ZipWriter.archive([("a.txt", Data(String(repeating: "abc", count: 100).utf8))])
    // 中身の途中で切れている（中央ディレクトリだけ残す）
    var cut = zip
    cut.removeSubrange(30..<40)

    // When / Then
    #expect(throws: SpreadsheetFileError.notZip) { try ZipArchive(zip.prefix(zip.count - 1)) }
    #expect(throws: SpreadsheetFileError.notZip) { try ZipArchive(Data("not a zip".utf8)) }
    // 先頭を削ると、申告された位置がずれる
    #expect(throws: SpreadsheetFileError.corrupted) { try ZipArchive(zip.dropFirst(10)) }
    #expect(throws: SpreadsheetFileError.self) {
      var archive = try ZipArchive(cut)
      _ = try archive.read("a.txt")
    }
  }

  @Test("中身が書き換わっていれば、読むときに CRC の食い違いとして断る")
  func badChecksum() throws {
    // Given: "xy" は縮まないので無圧縮で入る。中身の 1 バイトを書き換える
    var zip = try ZipWriter.archive([("x", Data("xy".utf8))])
    zip[zip.range(of: Data("xy".utf8))!.lowerBound] = UInt8(ascii: "z")

    // When
    var archive = try ZipArchive(zip)

    // Then
    #expect(throws: SpreadsheetFileError.checksumMismatch("x")) { try archive.read("x") }
  }

  @Test("展開後の大きさを上限より大きく申告していれば、確保する前に断る")
  func declaredTooLarge() throws {
    // Given
    let zip = try bomb()
    let huge = patched(zip, at: centralDirectoryEntry(zip) + 24, UInt32(ZipArchive.maxEntrySize + 1))

    // When
    var archive = try ZipArchive(huge)

    // Then
    #expect(throws: SpreadsheetFileError.tooLarge) { try archive.read("bomb") }
  }

  @Test("展開後の大きさを小さく偽っても、申告 + 1 バイトしか展開せず食い違いとして断る")
  func declaredTooSmall() throws {
    // Given: 1MB の 0 は 10KB 未満に縮む。申告は 1000 バイトにする
    let zip = try bomb()
    #expect(zip.count < 10_000)
    let lying = patched(zip, at: centralDirectoryEntry(zip) + 24, UInt32(1000))

    // When
    var archive = try ZipArchive(lying)

    // Then
    #expect(throws: SpreadsheetFileError.corrupted) { try archive.read("bomb") }
  }

  @Test("項目の数が多すぎる ZIP は断る")
  func tooManyEntries() throws {
    // Given: 終端レコードの項目数（このディスク・全体）を 10,001 にする
    let zip = try bomb()
    let end = endOfCentralDirectory(zip)
    let many = patched(patched(zip, at: end + 8, UInt16(10_001)), at: end + 10, UInt16(10_001))

    // When / Then
    #expect(throws: SpreadsheetFileError.tooLarge) { try ZipArchive(many) }
  }

  @Test("ZIP64 は開くときに断る")
  func zip64() throws {
    // Given: 中央ディレクトリの位置を ZIP64 の印 0xFFFFFFFF にする
    let zip = try ZipWriter.archive([("a", Data("hello".utf8))])
    let zip64 = patched(zip, at: endOfCentralDirectory(zip) + 16, UInt32(0xFFFF_FFFF))

    // When / Then
    #expect(throws: SpreadsheetFileError.unsupportedZip("ZIP64")) { try ZipArchive(zip64) }
  }

  @Test("扱えない項目は開けても、読むときに断る", arguments: [
    // 汎用ビットフラグ（+8）の暗号化の印
    (8, [1, 0], SpreadsheetFileError.unsupportedZip("暗号化された ZIP")),
    // 圧縮方式（+10）を 12（bzip2）にする
    (10, [12, 0], .unsupportedZip("圧縮方式 12")),
    // ローカルヘッダーの位置（+42）を範囲外にする
    (42, [0x00, 0xFF, 0xFF, 0xFF], .corrupted),
  ] as [(Int, [UInt8], SpreadsheetFileError)])
  func unsupportedEntry(field: Int, bytes: [UInt8], expected: SpreadsheetFileError) throws {
    // Given: 中央ディレクトリの項目の field バイト目から bytes を書き込む
    var zip = try ZipWriter.archive([("a", Data("hello".utf8))])
    let at = centralDirectoryEntry(zip) + field
    zip.replaceSubrange(at..<at + bytes.count, with: bytes)

    // When
    var archive = try ZipArchive(zip)

    // Then
    #expect(throws: expected) { try archive.read("a") }
  }

  @Test("同じ名前の項目が 2 つある ZIP は断る")
  func duplicatedNames() throws {
    // Given
    let duplicated = try ZipWriter.archive([("a", Data("1".utf8)), ("a", Data("2".utf8))])

    // When / Then
    #expect(throws: SpreadsheetFileError.corrupted) { try ZipArchive(duplicated) }
  }
}
