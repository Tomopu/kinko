import Foundation

/// .kinko ファイルの形式。数値はすべてビッグエンディアン
///
/// バージョン 1（パスワードだけで開く）
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
///
/// バージョン 2（この Mac 専用。パスワードとこの Mac の Secure Enclave の鍵の両方で開く。復旧コードでも開ける）
///
///   位置  長さ
///     0    30  バージョン 1 と同じ（形式バージョンは 2）
///    30    65  使い捨ての公開鍵（P-256、X9.63 非圧縮）。Secure Enclave の鍵と ECDH して、共有の秘密を作る
///    95    12  パスワード＋Mac の鍵でデータ鍵を包んだときの nonce
///   107    48  パスワード＋Mac の鍵で包んだデータ鍵
///   155    12  復旧コードでデータ鍵を包んだときの nonce
///   203    48  復旧コードで包んだデータ鍵
///   251    12  本文の nonce
///   263     …  本文の暗号文 + 認証タグ 16 バイト
///
/// 0〜94（鍵の作り方と使い捨ての公開鍵）を、データ鍵を包むときの AAD にする。0〜262 を本文の AAD にする
enum VaultFile {
  static let magic = Data("KNKO".utf8)
  static let version: UInt8 = 1
  static let deviceBoundVersion: UInt8 = 2
  static let kdfArgon2id: UInt8 = 1
  static let nonceLength = 12
  static let tagLength = 16
  static let prefixLength = 30
  static let wrappedKeyLength = KeyDerivation.keyLength + tagLength
  /// バージョン 1 のヘッダの長さ
  static let headerLength = prefixLength + nonceLength + wrappedKeyLength + nonceLength
  static let publicKeyLength = 65
  static let deviceBoundPrefixLength = prefixLength + publicKeyLength
  static let deviceBoundHeaderLength = deviceBoundPrefixLength + 2 * (nonceLength + wrappedKeyLength) + nonceLength

  struct Parsed {
    var envelope: VaultEnvelope
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
    guard fileVersion == version || fileVersion == deviceBoundVersion else { throw VaultError.unsupportedVersion(fileVersion) }
    let kdf = try reader.readByte()
    guard kdf == kdfArgon2id else { throw VaultError.unsupportedKDF(kdf) }
    let parameters = KDFParameters(memoryKiB: try reader.readUInt32(), iterations: try reader.readUInt32())
    // 重い鍵導出を始める前に弾く
    guard parameters.isAccepted else { throw VaultError.unacceptableParameters }
    let salt = try reader.read(KeyDerivation.saltLength)
    let envelope: VaultEnvelope
    if fileVersion == version {
      envelope = .password(
        KeyEnvelope(
          parameters: parameters, salt: salt,
          wrapNonce: try reader.read(nonceLength), wrappedKey: try reader.read(wrappedKeyLength)))
    } else {
      envelope = .deviceBound(
        DeviceBoundEnvelope(
          parameters: parameters, salt: salt,
          ephemeralPublicKey: try reader.read(publicKeyLength),
          passwordSlot: WrappedKey(nonce: try reader.read(nonceLength), sealed: try reader.read(wrappedKeyLength)),
          recoverySlot: WrappedKey(nonce: try reader.read(nonceLength), sealed: try reader.read(wrappedKeyLength))))
    }
    let bodyNonce = try reader.read(nonceLength)
    let body = reader.rest()
    guard body.count >= tagLength else { throw VaultError.truncated }
    let headerLength = file.count - body.count
    return Parsed(envelope: envelope, bodyNonce: bodyNonce, header: Data(file.prefix(headerLength)), body: body)
  }

  /// 0〜29（鍵の作り方）。バージョンだけが形式によって違う
  static func encodePrefix(version: UInt8, parameters: KDFParameters, salt: Data) -> Data {
    var data = magic
    data.append(version)
    data.append(kdfArgon2id)
    data.appendBigEndian(parameters.memoryKiB)
    data.appendBigEndian(parameters.iterations)
    data.append(salt)
    return data
  }
}

/// ヘッダのうち、データ鍵の包み方に関する部分（本文の nonce より前）。保存し直しても変わらない
enum VaultEnvelope: Sendable, Equatable {
  case password(KeyEnvelope)
  case deviceBound(DeviceBoundEnvelope)

  var salt: Data {
    switch self {
    case .password(let envelope): envelope.salt
    case .deviceBound(let envelope): envelope.salt
    }
  }

  var parameters: KDFParameters {
    switch self {
    case .password(let envelope): envelope.parameters
    case .deviceBound(let envelope): envelope.parameters
    }
  }

  var encoded: Data {
    switch self {
    case .password(let envelope): envelope.encoded
    case .deviceBound(let envelope): envelope.encoded
    }
  }
}

/// AES-GCM で包んだデータ鍵（暗号文 32 バイト + 認証タグ 16 バイト）と、そのときの nonce
struct WrappedKey: Sendable, Equatable {
  var nonce: Data
  var sealed: Data
}

/// バージョン 1：パスワードから作った鍵でデータ鍵を包む
struct KeyEnvelope: Sendable, Equatable {
  var parameters: KDFParameters
  var salt: Data
  var wrapNonce: Data
  var wrappedKey: Data

  static func encodePrefix(parameters: KDFParameters, salt: Data) -> Data {
    VaultFile.encodePrefix(version: VaultFile.version, parameters: parameters, salt: salt)
  }

  var encodedPrefix: Data { Self.encodePrefix(parameters: parameters, salt: salt) }
  var encoded: Data { encodedPrefix + wrapNonce + wrappedKey }
}

/// バージョン 2：パスワードとこの Mac の鍵の両方から作った鍵と、復旧コードから作った鍵で、同じデータ鍵を 2 つ包む
struct DeviceBoundEnvelope: Sendable, Equatable {
  var parameters: KDFParameters
  var salt: Data
  var ephemeralPublicKey: Data
  var passwordSlot: WrappedKey
  var recoverySlot: WrappedKey

  static func encodePrefix(parameters: KDFParameters, salt: Data, ephemeralPublicKey: Data) -> Data {
    VaultFile.encodePrefix(version: VaultFile.deviceBoundVersion, parameters: parameters, salt: salt) + ephemeralPublicKey
  }

  var encodedPrefix: Data { Self.encodePrefix(parameters: parameters, salt: salt, ephemeralPublicKey: ephemeralPublicKey) }
  var encoded: Data {
    encodedPrefix + passwordSlot.nonce + passwordSlot.sealed + recoverySlot.nonce + recoverySlot.sealed
  }
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
