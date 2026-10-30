import Foundation

/// 日付の表示形式と、シリアル値から日付の文字列への変換
extension XLSX {
  enum DateStyle: Equatable {
    /// 日付（時刻を含んでもよい）
    case date
    /// 時刻だけ（"h:mm" など）
    case time
  }

  /// 組み込みの書式番号のうち日付・時刻のもの。27〜36・50〜58 は日本語版の和暦・年月日の書式
  static func builtInDateStyle(_ id: Int) -> DateStyle? {
    switch id {
    case 14...17, 22, 27...31, 34...36, 50...58: .date
    case 18...21, 32, 33, 45...47: .time
    default: nil
    }
  }

  /// ユーザー定義の書式が日付・時刻かを、書式の記号から判断する。
  /// "..." の中・\ の直後・[Red] や [$-411] は飾りなので見ない。"0.00" や "#,##0" は日付ではない
  static func dateStyle(formatCode: String) -> DateStyle? {
    // 正と負などを ";" で分けた最初の部分だけを見る
    let characters = Array(formatCode.replacingOccurrences(of: "General", with: "", options: .caseInsensitive))
    var hasDate = false, hasMonthOrMinute = false, hasTime = false
    var index = 0
    while index < characters.count {
      let character = characters[index]
      switch character {
      case ";": index = characters.count
      case "\"":
        index += 1
        while index < characters.count, characters[index] != "\"" { index += 1 }
      case "\\", "_", "*": index += 1  // 次の 1 文字は記号ではなく、そのまま表示する文字
      case "[":
        var end = index + 1
        while end < characters.count, characters[end] != "]" { end += 1 }
        // [h] [mm] [ss] は経過時間。それ以外（[Red] [$-411] [>=100]）は無視する
        let inside = String(characters[min(index + 1, characters.count)..<min(end, characters.count)]).lowercased()
        if !inside.isEmpty, inside.allSatisfy({ "hms".contains($0) }) { hasTime = true }
        index = end
      case "y", "Y", "d", "D", "e", "g", "G":
        // "0.00E+00" の E は指数
        if character == "e", index + 1 < characters.count, "+-".contains(characters[index + 1]) { break }
        hasDate = true
      case "E":
        if index + 1 < characters.count, "+-".contains(characters[index + 1]) { break }
        hasDate = true
      case "h", "H", "s", "S": hasTime = true
      case "m", "M": hasMonthOrMinute = true
      case "A", "a":
        // AM/PM と A/P は 12 時間制の印（M を月と数えないよう、まとめて飛ばす）
        let rest = String(characters[index...]).uppercased()
        if rest.hasPrefix("AM/PM") {
          hasTime = true
          index += 4
        } else if rest.hasPrefix("A/P") {
          hasTime = true
          index += 2
        }
      default: break
      }
      index += 1
    }
    // m は h や s と一緒なら「分」、そうでなければ「月」
    if hasDate || (hasMonthOrMinute && !hasTime) { return .date }
    return hasTime ? .time : nil
  }

  /// 日付のシリアル値を文字列にする。日付は "yyyy/MM/dd"、時刻があれば " HH:mm"（秒があれば ":ss"）。
  /// Excel で表せない値（負や 9999 年より後）は nil
  static func dateText(serial: Double, style: DateStyle, date1904: Bool) -> String? {
    guard serial.isFinite, serial >= 0, serial < 2_958_466 else { return nil }
    let totalSeconds = Int((serial * 86_400).rounded())
    let days = totalSeconds / 86_400
    let seconds = totalSeconds % 86_400
    var time = String(format: "%02ld:%02ld", seconds / 3600, seconds / 60 % 60)
    if seconds % 60 != 0 { time += String(format: ":%02ld", seconds % 60) }
    if style == .time, serial < 1 { return time }

    let date: String
    if date1904 {
      date = civilDate(daysSince1970: days - 24_107)  // 1904 年基準: 0 = 1904-01-01
    } else if days == 60 {
      // Excel は Lotus 1-2-3 に合わせて、ない日付の 1900-02-29 を 60 番にしている
      date = "1900/02/29"
    } else if days < 60 {
      date = civilDate(daysSince1970: days - 25_568)  // 1 = 1900-01-01
    } else {
      date = civilDate(daysSince1970: days - 25_569)  // 61 = 1900-03-01（架空の 2/29 の分ずれる）
    }
    return seconds == 0 ? date : date + " " + time
  }

  /// 1970-01-01 からの日数を "yyyy/MM/dd" にする（タイムゾーンに左右されないよう、暦の計算を自前でする）
  private static func civilDate(daysSince1970: Int) -> String {
    // Howard Hinnant の civil_from_days
    let z = daysSince1970 + 719_468
    let era = (z >= 0 ? z : z - 146_096) / 146_097
    let dayOfEra = z - era * 146_097
    let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let monthIndex = (5 * dayOfYear + 2) / 153
    let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
    let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
    let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
    return String(format: "%04ld/%02ld/%02ld", year, month, day)
  }
}
