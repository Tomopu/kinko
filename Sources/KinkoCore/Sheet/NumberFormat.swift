import Foundation

/// 数の表示形式。値そのもの（計算に使う数）は変えず、見せ方だけを変える
public enum NumberFormat: Codable, Hashable, Sendable {
  /// 入力したとおり（計算結果は有効数字 15 桁）
  case general
  /// 1,234.50 のような形。grouping は 3 桁ごとのカンマ
  case number(decimals: Int, grouping: Bool)
  /// ¥1,235
  case currency(decimals: Int)
  /// 12.5%
  case percent(decimals: Int)

  public var decimals: Int {
    switch self {
    case .general: 0
    case .number(let decimals, _), .currency(let decimals), .percent(let decimals): decimals
    }
  }

  /// 小数点以下の桁を増やした（減らした）形式。0〜10 桁
  public func withDecimals(_ decimals: Int) -> NumberFormat {
    let decimals = max(0, min(10, decimals))
    switch self {
    case .general: return .number(decimals: decimals, grouping: false)
    case .number(_, let grouping): return .number(decimals: decimals, grouping: grouping)
    case .currency: return .currency(decimals: decimals)
    case .percent: return .percent(decimals: decimals)
    }
  }

  /// 表示する文字列。.general のときは nil（呼び出し側が入力どおりに見せる）
  public func format(_ number: Double) -> String? {
    switch self {
    case .general:
      return nil
    case .number(let decimals, let grouping):
      return Self.fixed(number, decimals: decimals, grouping: grouping)
    case .currency(let decimals):
      let text = Self.fixed(abs(number), decimals: decimals, grouping: true)
      return (number < 0 && text.contains(where: { $0 != "0" && $0 != "." && $0 != "," }) ? "-¥" : "¥") + text
    case .percent(let decimals):
      return Self.fixed(number * 100, decimals: decimals, grouping: false) + "%"
    }
  }

  /// 小数点以下を決まった桁に丸め、必要ならカンマを入れる
  private static func fixed(_ number: Double, decimals: Int, grouping: Bool) -> String {
    let decimals = max(0, min(10, decimals))
    // %f のまま丸めると 2.675（2 進数では 2.67499…）が 2.67 になるので、ROUND と同じ丸めを先にかける
    let rounded = Calculator.round(number, digits: decimals, rule: .toNearestOrAwayFromZero)
    var text = String(format: "%.\(decimals)f", rounded)
    if text.hasPrefix("-"), Double(text) == 0 { text.removeFirst() }
    guard grouping else { return text }
    let negative = text.hasPrefix("-")
    if negative { text.removeFirst() }
    let parts = text.split(separator: ".", maxSplits: 1)
    var integer = String(parts[0])
    var grouped = ""
    while integer.count > 3 {
      grouped = "," + integer.suffix(3) + grouped
      integer = String(integer.dropLast(3))
    }
    grouped = integer + grouped
    return (negative ? "-" : "") + grouped + (parts.count > 1 ? "." + parts[1] : "")
  }
}
