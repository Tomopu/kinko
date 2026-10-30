import Foundation

/// 表のファイル（.xlsx・.csv）の読み書きで起きるエラー。
/// 読むファイルは信用しない（壊れている・わざと細工されている）前提なので、理由ごとに分けて伝える
public enum SpreadsheetFileError: Error, LocalizedError, Equatable {
  /// ZIP として読めない（.xlsx の中身は ZIP）
  case notZip
  /// ZIP ではあるが .xlsx の部品（ブック本体）がない
  case notXLSX
  /// Excel 97-2003 の .xls（OLE2 形式）
  case legacyExcel
  /// パスワード付きの .xlsx（暗号化すると OLE2 形式の入れ物になる）
  case encryptedExcel
  /// 長さや位置が食い違っている・途中で切れている
  case corrupted
  /// ZIP64・暗号化・未対応の圧縮方式など、この実装が扱わない ZIP
  case unsupportedZip(String)
  /// 中身が CRC-32 と合わない（壊れているか改ざんされている）
  case checksumMismatch(String)
  /// 決めた上限を超える大きさ（ZIP 爆弾などから守るため）
  case tooLarge
  case tooManySheets(limit: Int)
  case tooManyCells(limit: Int)
  case tooManyRows(limit: Int)
  case tooManyColumns(limit: Int)
  case tooManyStyles(limit: Int)
  /// XML として読めない、または中身がおかしい部品
  case invalidPart(String)
  /// CSV の文字コードが分からない
  case unknownEncoding

  public var errorDescription: String? {
    switch self {
    case .notZip: "ZIP 形式のファイルではありません。"
    case .notXLSX: "Excel（.xlsx）のファイルではありません。"
    case .legacyExcel: "古い Excel 形式（.xls）は読めません。Excel で .xlsx として保存し直してください。"
    case .encryptedExcel: "パスワードで保護された Excel ファイルは読めません。Excel でパスワードを解除してから読み込んでください。"
    case .corrupted: "ファイルが壊れています。"
    case .unsupportedZip(let reason): "対応していない ZIP 形式です（\(reason)）。"
    case .checksumMismatch(let name): "ファイルの中身が壊れています（\(name) のチェックサムが合いません）。"
    case .tooLarge: "ファイルが大きすぎます。"
    case .tooManySheets(let limit): "シートが多すぎます（\(limit) 枚まで）。"
    case .tooManyCells(let limit): "セルが多すぎます（\(limit.formatted()) 個まで）。"
    case .tooManyRows(let limit): "行が多すぎます（\(limit.formatted()) 行まで）。"
    case .tooManyColumns(let limit): "列が多すぎます（\(limit.formatted()) 列まで）。"
    case .tooManyStyles(let limit): "セルの書式が多すぎます（\(limit.formatted()) 種類まで）。"
    case .invalidPart(let name): "ファイルの中身（\(name)）が読めません。"
    case .unknownEncoding: "文字コードが分かりません。UTF-8 か Shift_JIS で保存し直してください。"
    }
  }
}

/// 読み込みの上限。Kinko はワークスペース全体をメモリに持ち、保存のたびに丸ごと暗号化するので、
/// それに耐える大きさで打ち切る（Excel の上限よりずっと小さい）
enum SpreadsheetLimits {
  /// 中身のあるセルの数（全シートの合計）
  static let maxCells = 1_000_000
  /// 1 つのファイルとして受け付ける大きさ（CSV そのもの、.xlsx の ZIP そのもの）
  static let maxFileSize = 100 * 1024 * 1024
}
