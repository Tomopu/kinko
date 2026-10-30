import Foundation

/// .kinko ファイルの形式（バージョン 1）。数値はすべてビッグエンディアン
///
///   位置  長さ
///     0     4  マジック "KNKO"
///     4     1  形式バージョン（1）
///     5     1  鍵導出方式（1 = Argon2id v1.3）
///     6     4  Argon2id のメモリ量（KiB）
///    10     4  Argon2id の繰り返し回数
///    14    16  salt
///    30    12  データ鍵を包んだときの nonce
///    42    48  包んだデータ鍵（32 バイト + 認証タグ 16 バイト）
///    90    12  本文の nonce
///   102     …  本文の暗号文 + 認証タグ 16 バイト
///
/// 0〜29（鍵の作り方）を、データ鍵を包むときの AAD にする。
/// 0〜101（ヘッダ全体）を、本文を暗号化するときの AAD にする。
/// これでヘッダのどの 1 バイトを書き換えても復号が失敗し、改ざんに気づける。
enum VaultFile {
  static let magic = Data("KNKO".utf8)
  static let version: UInt8 = 1
  static let kdfArgon2id: UInt8 = 1
  static let nonceLength = 12
  static let tagLength = 16
  static let prefixLength = 30
  static let wrappedKeyLength = KeyDerivation.keyLength + tagLength
  static let headerLength = prefixLength + nonceLength + wrappedKeyLength + nonceLength

  struct Parsed {
    var envelope: KeyEnvelope
    var bodyNonce: Data
    /// 本文の AAD に使うヘッダ全体
    var header: Data
    /// 本文の暗号文 + 認証タグ
    var body: Data
  }

  static func parse(_ file: Data) throws -> Parsed {
    var reader = ByteReader(Data(file))
    guard try reader.read(magic.count) == magic else { throw VaultError.notAVault }
    let fileVersion = try reader.readByte()
    guard fileVersion == version else { throw VaultError.unsupportedVersion(fileVersion) }
    let kdf = try reader.readByte()
    guard kdf == kdfArgon2id else { throw VaultError.unsupportedKDF(kdf) }
    let parameters = KDFParameters(memoryKiB: try reader.readUInt32(), iterations: try reader.readUInt32())
    // 重い鍵導出を始める前に弾く
    guard parameters.isAccepted else { throw VaultError.unacceptableParameters }
    let salt = try reader.read(KeyDerivation.saltLength)
    let envelope = KeyEnvelope(
      parameters: parameters,
      salt: salt,
      wrapNonce: try reader.read(nonceLength),
      wrappedKey: try reader.read(wrappedKeyLength))
    let bodyNonce = try reader.read(nonceLength)
    let body = reader.rest()
    guard body.count >= tagLength else { throw VaultError.truncated }
    return Parsed(envelope: envelope, bodyNonce: bodyNonce, header: Data(file.prefix(headerLength)), body: body)
  }
}

/// ヘッダのうち、データ鍵の包み方に関する部分。保存し直しても変わらない
struct KeyEnvelope: Sendable, Equatable {
  var parameters: KDFParameters
  var salt: Data
  var wrapNonce: Data
  var wrappedKey: Data

  static func encodePrefix(parameters: KDFParameters, salt: Data) -> Data {
    var data = VaultFile.magic
    data.append(VaultFile.version)
    data.append(VaultFile.kdfArgon2id)
    data.appendBigEndian(parameters.memoryKiB)
    data.appendBigEndian(parameters.iterations)
    data.append(salt)
    return data
  }

  var encodedPrefix: Data { Self.encodePrefix(parameters: parameters, salt: salt) }
  var encoded: Data { encodedPrefix + wrapNonce + wrappedKey }
}

private struct ByteReader {
  private let data: Data
  private var offset = 0

  init(_ data: Data) { self.data = data }

  mutating func read(_ count: Int) throws -> Data {
    guard data.count - offset >= count else { throw VaultError.truncated }
    defer { offset += count }
    return data.subdata(in: offset..<(offset + count))
  }

  mutating func readByte() throws -> UInt8 { try read(1)[0] }

  mutating func readUInt32() throws -> UInt32 {
    try read(4).reduce(0) { $0 << 8 | UInt32($1) }
  }

  func rest() -> Data { data.subdata(in: offset..<data.count) }
}

extension Data {
  fileprivate mutating func appendBigEndian(_ value: UInt32) {
    Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
  }
}
