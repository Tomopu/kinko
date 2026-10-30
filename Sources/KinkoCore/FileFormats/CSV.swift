import Foundation

/// CSV（RFC 4180）を読み書きする
public enum CSV {
  /// Windows の Shift_JIS（CP932）。Foundation の .shiftJIS は機種依存文字（①・髙 など）を含まないので、こちらを使う
  private static let cp932 = String.Encoding(
    rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))

  /// UTF-8（BOM あり・なし）、BOM 付き UTF-16、それ以外は CP932（Windows の Shift_JIS、日本語版 Excel の既定）として読む
  public static func read(_ data: Data, name: String, separator: Character = ",") throws -> Sheet {
    guard data.count <= SpreadsheetLimits.maxFileSize else { throw SpreadsheetFileError.tooLarge }
    guard let text = decode(data) else { throw SpreadsheetFileError.unknownEncoding }
    let separator = separator.unicodeScalars.first ?? ","

    var cells: [CellAddress: String] = [:]
    var row = 0
    var column = 0
    var field = String.UnicodeScalarView()
    var quoted = false
    /// 引用符の中で " が来た直後（次が " なら "" で 1 文字の "、そうでなければ引用の終わり）
    var quoteEnded = false
    /// 前の文字が CR だった（CRLF の LF を、もう 1 つの改行と数えない）
    var afterCR = false
    /// 今の行に何か（区切りや文字）があった
    var rowHasContent = false

    func endField() throws {
      guard column < CellAddress.maxColumns else { throw SpreadsheetFileError.tooManyColumns(limit: CellAddress.maxColumns) }
      guard row < CellAddress.maxRows else { throw SpreadsheetFileError.tooManyRows(limit: CellAddress.maxRows) }
      if !field.isEmpty {
        let value = String(field)
        // CSV の中の数式は計算しない（文字列として入れる）。よそから来たファイルに "=HYPERLINK(...)" などを仕込み、
        // 開いた人の画面で勝手に動かす「CSV インジェクション」を防ぐため。"'" で始まる値も、そのまま見えるように "'" を足す
        cells[CellAddress(row: row, column: column)] = value.hasPrefix("=") || value.hasPrefix("'") ? "'" + value : value
        guard cells.count <= SpreadsheetLimits.maxCells else {
          throw SpreadsheetFileError.tooManyCells(limit: SpreadsheetLimits.maxCells)
        }
      }
      field = String.UnicodeScalarView()
      column += 1
      quoted = false
      quoteEnded = false
    }

    func endRow() throws {
      try endField()
      row += 1
      column = 0
      rowHasContent = false
    }

    for scalar in text.unicodeScalars {
      if afterCR {
        afterCR = false
        if scalar == "\n" { continue }
      }
      if quoted && !quoteEnded {
        if scalar == "\"" { quoteEnded = true } else { field.append(scalar) }
        continue
      }
      if quoteEnded {
        quoteEnded = false
        if scalar == "\"" {
          field.append(scalar)
          continue
        }
        // 閉じた引用符の後ろは、区切りか改行のはず。ほかの文字が来ても捨てずに続けて読む（壊れた CSV にも寛容に）
        quoted = false
      }
      rowHasContent = true
      switch scalar {
      case separator: try endField()
      case "\r":
        try endRow()
        afterCR = true
      case "\n": try endRow()
      // 項目の先頭の " だけが引用の始まり
      case "\"" where field.isEmpty && !quoted: quoted = true
      default: field.append(scalar)
      }
    }
    // 最後の行が改行で終わっていなくても読む（引用符が閉じていなくても、そこまでを値にする）
    if rowHasContent || quoted { try endRow() }
    return Sheet(name: name, cells: cells)
  }

  /// 表示される値を書く。UTF-8（BOM 付き。Excel が日本語を化けさせないため）、改行は CRLF
  public static func write(_ sheet: Sheet, values: (CellAddress) -> CellValue, separator: Character = ",") -> Data {
    var text = "\u{FEFF}"
    // 左上は A1 から書く（位置を保つため）。右下は中身のある範囲の端まで
    if let end = sheet.usedRange?.end {
      for row in 0...end.row {
        let fields = (0...end.column).map { column in
          quote(values(CellAddress(row: row, column: column)).displayText, separator: separator)
        }
        text += fields.joined(separator: String(separator)) + "\r\n"
      }
    }
    return Data(text.utf8)
  }

  /// 区切り・引用符・改行を含むときだけ引用符で囲む（中の " は "" にする）
  private static func quote(_ field: String, separator: Character) -> String {
    guard field.unicodeScalars.contains(where: { $0 == "\"" || $0 == "\r" || $0 == "\n" }) || field.contains(separator)
    else { return field }
    return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
  }

  private static func decode(_ data: Data) -> String? {
    let bytes = [UInt8](data.prefix(3))
    if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { return String(data: data.dropFirst(3), encoding: .utf8) }
    if bytes.starts(with: [0xFF, 0xFE]) { return String(data: data.dropFirst(2), encoding: .utf16LittleEndian) }
    if bytes.starts(with: [0xFE, 0xFF]) { return String(data: data.dropFirst(2), encoding: .utf16BigEndian) }
    // BOM がなければ、UTF-8 として正しく読めるかを先に試す（CP932 のバイト列が UTF-8 として正しくなることはまずない）
    return String(data: data, encoding: .utf8) ?? String(data: data, encoding: cp932)
  }
}
