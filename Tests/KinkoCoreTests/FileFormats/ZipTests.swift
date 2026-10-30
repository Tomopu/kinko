import Foundation
import Testing

@testable import KinkoCore

/// 中央ディレクトリの最初の項目の位置
private func centralDirectoryEntry(_ zip: Data) -> Int {
  zip.range(of: Data([0x50, 0x4B, 0x01, 0x02]))!.lowerBound
}

private func endOfCentralDirectory(_ zip: Data) -> Int {
  zip.range(of: Data([0x50, 0x4B, 0x05, 0x06]), options: .backwards)!.lowerBound
}

private func patch32(_ data: inout Data, at offset: Int, _ value: UInt32) {
  for index in 0..<4 { data[offset + index] = UInt8((value >> (8 * UInt32(index))) & 0xFF) }
}

private func patch16(_ data: inout Data, at offset: Int, _ value: UInt16) {
  data[offset] = UInt8(value & 0xFF)
  data[offset + 1] = UInt8(value >> 8)
}

@Test func crc32KnownVector() {
  #expect(CRC32.checksum(Array("123456789".utf8)) == 0xCBF4_3926)
  #expect(CRC32.checksum([UInt8]()) == 0)
}

@Test func zipRoundTrip() throws {
  let repeated = Data(String(repeating: "Kinko の表。", count: 500).utf8)
  let random = Data((0..<300).map { _ in UInt8.random(in: 0...255) })
  let zip = try ZipWriter.archive([("a.xml", repeated), ("空", Data()), ("フォルダ/乱数.bin", random)])
  // 繰り返しの多い中身は圧縮されている
  #expect(zip.count < repeated.count)
  var archive = try ZipArchive(zip)
  #expect(try archive.read("a.xml") == repeated)
  #expect(try archive.read("空") == Data())
  #expect(try archive.read("フォルダ/乱数.bin") == random)
  #expect(try archive.read("ない") == nil)
  #expect(archive.entries["フォルダ/乱数.bin"]?.method == 0)  // 乱数は縮まないので無圧縮
  // 日時は 1980-01-01 00:00 に固定（ローカルヘッダーの 10〜13 バイト目）
  #expect(Array(zip[10..<14]) == [0, 0, 0x21, 0])
}

@Test func zipRejectsTruncatedData() throws {
  let zip = try ZipWriter.archive([("a.txt", Data(String(repeating: "abc", count: 100).utf8))])
  #expect(throws: SpreadsheetFileError.notZip) { try ZipArchive(zip.prefix(zip.count - 1)) }
  #expect(throws: SpreadsheetFileError.notZip) { try ZipArchive(Data("not a zip".utf8)) }
  // 先頭を削ると、申告された位置がずれる
  #expect(throws: SpreadsheetFileError.corrupted) { try ZipArchive(zip.dropFirst(10)) }
  // 中身の途中で切れている（中央ディレクトリだけ残す）
  var cut = zip
  cut.removeSubrange(30..<40)
  #expect(throws: SpreadsheetFileError.self) {
    var archive = try ZipArchive(cut)
    _ = try archive.read("a.txt")
  }
}

@Test func zipRejectsBadChecksum() throws {
  // "xy" は縮まないので無圧縮で入る。中身の 1 バイトを書き換える
  var zip = try ZipWriter.archive([("x", Data("xy".utf8))])
  let content = zip.range(of: Data("xy".utf8))!.lowerBound
  zip[content] = UInt8(ascii: "z")
  var archive = try ZipArchive(zip)
  #expect(throws: SpreadsheetFileError.checksumMismatch("x")) { try archive.read("x") }
}

@Test func zipRejectsOversizedEntries() throws {
  let zeros = Data(count: 1_000_000)
  let zip = try ZipWriter.archive([("bomb", zeros)])
  #expect(zip.count < 10_000)

  // 展開後の大きさを上限より大きく申告していれば、確保する前に断る
  var huge = zip
  patch32(&huge, at: centralDirectoryEntry(huge) + 24, UInt32(ZipArchive.maxEntrySize + 1))
  var archive = try ZipArchive(huge)
  #expect(throws: SpreadsheetFileError.tooLarge) { try archive.read("bomb") }

  // 小さく偽って申告しても、申告 + 1 バイトしか展開しないので食い違いとして断る
  var lying = zip
  patch32(&lying, at: centralDirectoryEntry(lying) + 24, 1000)
  archive = try ZipArchive(lying)
  #expect(throws: SpreadsheetFileError.corrupted) { try archive.read("bomb") }

  // 項目の数が多すぎる
  var many = zip
  patch16(&many, at: endOfCentralDirectory(many) + 8, 10_001)
  patch16(&many, at: endOfCentralDirectory(many) + 10, 10_001)
  #expect(throws: SpreadsheetFileError.tooLarge) { try ZipArchive(many) }
}

@Test func zipRejectsUnsupportedFeatures() throws {
  let zip = try ZipWriter.archive([("a", Data("hello".utf8))])

  var zip64 = zip
  patch32(&zip64, at: endOfCentralDirectory(zip64) + 16, 0xFFFF_FFFF)
  #expect(throws: SpreadsheetFileError.unsupportedZip("ZIP64")) { try ZipArchive(zip64) }

  var encrypted = zip
  patch16(&encrypted, at: centralDirectoryEntry(encrypted) + 8, 1)
  var archive = try ZipArchive(encrypted)
  #expect(throws: SpreadsheetFileError.unsupportedZip("暗号化された ZIP")) { try archive.read("a") }

  var bzip2 = zip
  patch16(&bzip2, at: centralDirectoryEntry(bzip2) + 10, 12)
  archive = try ZipArchive(bzip2)
  #expect(throws: SpreadsheetFileError.unsupportedZip("圧縮方式 12")) { try archive.read("a") }

  // 同じ名前が 2 つ
  let duplicated = try ZipWriter.archive([("a", Data("1".utf8)), ("a", Data("2".utf8))])
  #expect(throws: SpreadsheetFileError.corrupted) { try ZipArchive(duplicated) }

  // ローカルヘッダーの位置を範囲外にする
  var outOfRange = zip
  patch32(&outOfRange, at: centralDirectoryEntry(outOfRange) + 42, 0xFFFF_FF00)
  archive = try ZipArchive(outOfRange)
  #expect(throws: SpreadsheetFileError.corrupted) { try archive.read("a") }
}
