import Compression
import Foundation

/// CRC-32（ZIP・PNG などと同じ多項式 0xEDB88320）。ZIP の各ファイルが壊れていないかを確かめるのに使う
enum CRC32 {
  /// 1 バイトずつの計算を速くするための表（256 通りの結果を先に作っておく）
  private static let table: [UInt32] = (0..<256).map { index in
    var value = UInt32(index)
    for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
    return value
  }

  static func checksum(_ bytes: some Sequence<UInt8>) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in bytes { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
    return ~crc
  }
}

/// ZIP を読む。.xlsx は ZIP の中に XML を入れたものなので、そのために必要な分だけを実装する。
///
/// ZIP は「どこに何バイトある」をファイル自身が申告する形式なので、細工されたファイルは
/// 範囲外の位置や、展開すると何 GB にもなる大きさ（ZIP 爆弾）を申告してくる。
/// そこで申告された位置・長さは使う前にすべて範囲を確かめ、大きさは確保する前に上限と比べる
struct ZipArchive {
  /// .xlsx の部品はふつう数十個。1 万を超えるのは異常なので打ち切る（中央ディレクトリの読み込みで時間を使わせない）
  static let maxEntryCount = 10_000
  /// 1 つの部品の展開後の大きさ。100 万セルのシートの XML でも 100 MB には届かない
  static let maxEntrySize = 100 * 1024 * 1024
  /// 展開した合計。1 つずつは上限内でも、数を並べてメモリを使い切らせる攻撃を防ぐ
  static let maxTotalSize = 300 * 1024 * 1024

  struct Entry {
    var name: String
    var flags: Int
    var method: Int
    var crc32: UInt32
    var compressedSize: Int
    var uncompressedSize: Int
    var localHeaderOffset: Int
  }

  private let bytes: [UInt8]
  /// 中央ディレクトリが始まる位置。各ファイルの中身はこれより前にあるはず
  private let centralDirectoryOffset: Int
  private(set) var entries: [String: Entry] = [:]
  /// これまでに展開したバイト数（maxTotalSize と比べる）
  private var extractedSize = 0

  init(_ data: Data) throws(SpreadsheetFileError) {
    guard data.count <= SpreadsheetLimits.maxFileSize else { throw .tooLarge }
    bytes = [UInt8](data)

    // 末尾の End of Central Directory（22 バイト + 最大 65,535 バイトのコメント）を後ろから探す
    let minimumEnd = 22
    guard bytes.count >= minimumEnd else { throw .notZip }
    var end: Int?
    var position = bytes.count - minimumEnd
    let lowest = max(0, bytes.count - minimumEnd - 0xFFFF)
    while position >= lowest {
      if Self.u32(bytes, position) == 0x0605_4B50, position + minimumEnd + Self.u16(bytes, position + 20) <= bytes.count {
        end = position
        break
      }
      position -= 1
    }
    guard let end else { throw .notZip }

    // ZIP64 は「本当の値は別の場所にある」という印として 0xFFFF / 0xFFFFFFFF を入れる
    if end >= 20, Self.u32(bytes, end - 20) == 0x0706_4B50 { throw .unsupportedZip("ZIP64") }
    let entryCount = Self.u16(bytes, end + 10)
    let directorySize = Self.u32(bytes, end + 12)
    let directoryOffset = Self.u32(bytes, end + 16)
    if entryCount == 0xFFFF || directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF {
      throw .unsupportedZip("ZIP64")
    }
    guard Self.u16(bytes, end + 4) == 0, Self.u16(bytes, end + 6) == 0, Self.u16(bytes, end + 8) == entryCount else {
      throw .unsupportedZip("複数ファイルへの分割")
    }
    guard entryCount <= Self.maxEntryCount else { throw .tooLarge }
    guard directoryOffset + directorySize <= end else { throw .corrupted }
    centralDirectoryOffset = directoryOffset

    var cursor = directoryOffset
    let directoryEnd = directoryOffset + directorySize
    for _ in 0..<entryCount {
      guard cursor + 46 <= directoryEnd, Self.u32(bytes, cursor) == 0x0201_4B50 else { throw .corrupted }
      let nameLength = Self.u16(bytes, cursor + 28)
      let extraLength = Self.u16(bytes, cursor + 30)
      let commentLength = Self.u16(bytes, cursor + 32)
      let next = cursor + 46 + nameLength + extraLength + commentLength
      guard next <= directoryEnd else { throw .corrupted }
      let entry = Entry(
        name: Self.decodeName(bytes[(cursor + 46)..<(cursor + 46 + nameLength)]),
        flags: Self.u16(bytes, cursor + 8),
        method: Self.u16(bytes, cursor + 10),
        crc32: UInt32(Self.u32(bytes, cursor + 16)),
        compressedSize: Self.u32(bytes, cursor + 20),
        uncompressedSize: Self.u32(bytes, cursor + 24),
        localHeaderOffset: Self.u32(bytes, cursor + 42))
      if entry.compressedSize == 0xFFFF_FFFF || entry.uncompressedSize == 0xFFFF_FFFF || entry.localHeaderOffset == 0xFFFF_FFFF {
        throw .unsupportedZip("ZIP64")
      }
      // 同じ名前が 2 つあると、読む道具によって違う方を読む（検査をすり抜ける手口になる）ので受け付けない
      guard entries[entry.name] == nil else { throw .corrupted }
      entries[entry.name] = entry
      cursor = next
    }
  }

  func contains(_ name: String) -> Bool { entries[name] != nil }

  /// 名前で 1 つ取り出す。なければ nil。必要な部品だけを展開する（全部は展開しない）
  mutating func read(_ name: String) throws(SpreadsheetFileError) -> Data? {
    guard let entry = entries[name] else { return nil }
    guard entry.flags & 1 == 0 else { throw .unsupportedZip("暗号化された ZIP") }
    guard entry.method == 0 || entry.method == 8 else { throw .unsupportedZip("圧縮方式 \(entry.method)") }
    // 確保する前に、申告された大きさを上限と比べる
    guard entry.uncompressedSize <= Self.maxEntrySize, extractedSize + entry.uncompressedSize <= Self.maxTotalSize else {
      throw .tooLarge
    }

    // ローカルヘッダーは名前と拡張領域の長さを知るためだけに読む（大きさは中央ディレクトリの値を使う。
    // ローカル側は後ろにデータ記述子を置く書き方だと 0 になっていることがある）
    let header = entry.localHeaderOffset
    guard header + 30 <= centralDirectoryOffset, Self.u32(bytes, header) == 0x0403_4B50 else { throw .corrupted }
    let nameLength = Self.u16(bytes, header + 26)
    let extraLength = Self.u16(bytes, header + 28)
    let start = header + 30 + nameLength + extraLength
    guard start <= centralDirectoryOffset, entry.compressedSize <= centralDirectoryOffset - start,
      Self.decodeName(bytes[(header + 30)..<(header + 30 + nameLength)]) == entry.name
    else { throw .corrupted }
    let compressed = bytes[start..<(start + entry.compressedSize)]

    let output: [UInt8]
    if entry.method == 0 {
      guard entry.compressedSize == entry.uncompressedSize else { throw .corrupted }
      output = Array(compressed)
    } else if entry.uncompressedSize == 0 {
      output = []
    } else {
      // 申告より 1 バイト大きい入れ物に展開する。入れ物がいっぱいになったら申告より大きい中身なので拒否できる
      // （申告どおりの大きさしか確保しないので、申告を偽っても上限を超えてメモリを使わせることはできない）
      let capacity = entry.uncompressedSize + 1
      output = compressed.withUnsafeBufferPointer { source in
        [UInt8](unsafeUninitializedCapacity: capacity) { buffer, count in
          guard let destination = buffer.baseAddress, let source = source.baseAddress else {
            count = 0
            return
          }
          // COMPRESSION_ZLIB は zlib のヘッダーなしの生の DEFLATE（ZIP の方式 8 と同じもの）
          count = compression_decode_buffer(destination, capacity, source, entry.compressedSize, nil, COMPRESSION_ZLIB)
        }
      }
      guard output.count == entry.uncompressedSize else { throw .corrupted }
    }
    guard CRC32.checksum(output) == entry.crc32 else { throw .checksumMismatch(entry.name) }
    extractedSize += output.count
    return Data(output)
  }

  /// 名前は UTF-8 で読む（.xlsx の部品名は ASCII）。UTF-8 でなければ 1 バイト 1 文字として読む
  private static func decodeName(_ bytes: ArraySlice<UInt8>) -> String {
    String(bytes: bytes, encoding: .utf8) ?? String(decoding: bytes.map { UInt16($0) }, as: UTF16.self)
  }

  /// リトルエンディアンの整数を読む。呼ぶ側で範囲を確かめてあるが、念のためここでも外れたら 0 を返す
  /// （0 はどの署名とも合わないので、範囲外を読んでも先へは進まない）
  private static func u16(_ bytes: [UInt8], _ offset: Int) -> Int {
    guard offset >= 0, offset + 2 <= bytes.count else { return 0 }
    return Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
  }

  private static func u32(_ bytes: [UInt8], _ offset: Int) -> Int {
    guard offset >= 0, offset + 4 <= bytes.count else { return 0 }
    return u16(bytes, offset) | u16(bytes, offset + 2) << 16
  }
}

/// ZIP を書く。.xlsx を書き出すためのもの
enum ZipWriter {
  /// 日時はわざと 1980-01-01 00:00（DOS 形式で表せる最小）に固定する。
  /// 実際の日時を書くと、書き出したファイルからいつ作業していたかが漏れるため
  private static let dosTime: UInt16 = 0
  private static let dosDate: UInt16 = (0 << 9) | (1 << 5) | 1

  /// files の順に格納する。名前は "/" 区切りの相対パス
  static func archive(_ files: [(name: String, data: Data)]) throws(SpreadsheetFileError) -> Data {
    guard files.count < 0xFFFF else { throw .tooLarge }
    var output = Data()
    var directory = Data()
    for file in files {
      let name = Data(file.name.utf8)
      let raw = [UInt8](file.data)
      let crc = CRC32.checksum(raw)
      var method: UInt16 = 0
      var stored = raw
      // 縮まらなければ（すでに圧縮された中身や、ごく小さいもの）無圧縮で入れる
      if let deflated = deflate(raw) {
        method = 8
        stored = deflated
      }
      // ZIP64 は書かないので、4 GB を超えるものは作れない
      guard raw.count < 0xFFFF_FFFF, output.count + stored.count + name.count + 30 < 0xFFFF_FFFF else { throw .tooLarge }
      let offset = output.count

      // 汎用フラグ: ビット 11 = 名前が UTF-8
      let flags: UInt16 = 1 << 11
      var local = Data()
      append32(&local, 0x0403_4B50)
      append16(&local, 20)  // 展開に必要なバージョン（2.0: DEFLATE）
      append16(&local, flags)
      append16(&local, method)
      append16(&local, dosTime)
      append16(&local, dosDate)
      append32(&local, crc)
      append32(&local, UInt32(stored.count))
      append32(&local, UInt32(raw.count))
      append16(&local, UInt16(name.count))
      append16(&local, 0)
      output += local
      output += name
      output += stored

      append32(&directory, 0x0201_4B50)
      append16(&directory, 20)  // 作成したバージョン
      append16(&directory, 20)
      append16(&directory, flags)
      append16(&directory, method)
      append16(&directory, dosTime)
      append16(&directory, dosDate)
      append32(&directory, crc)
      append32(&directory, UInt32(stored.count))
      append32(&directory, UInt32(raw.count))
      append16(&directory, UInt16(name.count))
      append16(&directory, 0)  // 拡張領域
      append16(&directory, 0)  // コメント
      append16(&directory, 0)  // 開始ディスク
      append16(&directory, 0)  // 内部属性
      append32(&directory, 0)  // 外部属性
      append32(&directory, UInt32(offset))
      directory += name
    }
    let directoryOffset = output.count
    guard directoryOffset + directory.count < 0xFFFF_FFFF else { throw .tooLarge }
    output += directory
    append32(&output, 0x0605_4B50)
    append16(&output, 0)
    append16(&output, 0)
    append16(&output, UInt16(files.count))
    append16(&output, UInt16(files.count))
    append32(&output, UInt32(directory.count))
    append32(&output, UInt32(directoryOffset))
    append16(&output, 0)
    return output
  }

  /// 生の DEFLATE で圧縮する。元より小さくならなければ nil
  private static func deflate(_ raw: [UInt8]) -> [UInt8]? {
    guard raw.count > 0 else { return nil }
    let capacity = raw.count
    let result = raw.withUnsafeBufferPointer { source in
      [UInt8](unsafeUninitializedCapacity: capacity) { buffer, count in
        // 入れ物に収まらなければ 0 が返る（＝縮まなかった）
        count = compression_encode_buffer(buffer.baseAddress!, capacity, source.baseAddress!, raw.count, nil, COMPRESSION_ZLIB)
      }
    }
    return result.isEmpty || result.count >= raw.count ? nil : result
  }

  private static func append16(_ data: inout Data, _ value: UInt16) {
    data.append(UInt8(value & 0xFF))
    data.append(UInt8(value >> 8))
  }

  private static func append32(_ data: inout Data, _ value: UInt32) {
    append16(&data, UInt16(value & 0xFFFF))
    append16(&data, UInt16(value >> 16))
  }
}
