import Foundation

public enum CellError: String, Error, Sendable, CaseIterable {
  case div0 = "#DIV/0!"
  case value = "#VALUE!"
  case ref = "#REF!"
  case name = "#NAME?"
  case num = "#NUM!"
  case na = "#N/A"
  case null = "#NULL!"
  /// 自分自身を参照している（Excel にはない表示。Excel は警告を出して 0 にする）
  case circular = "#CIRC!"
}

/// セルの値（数式なら計算した結果）
public enum CellValue: Equatable, Sendable {
  case empty
  case number(Double)
  case text(String)
  case bool(Bool)
  case error(CellError)

  public var displayText: String {
    switch self {
    case .empty: ""
    case .number(let number): Self.format(number)
    case .text(let text): text
    case .bool(let bool): bool ? "TRUE" : "FALSE"
    case .error(let error): error.rawValue
    }
  }

  /// 有効数字 15 桁で表示する（0.1 + 0.2 が 0.30000000000000004 にならないように。Excel と同じ桁数）
  public static func format(_ number: Double) -> String {
    if number == 0 { return "0" }
    return String(format: "%.15g", number)
  }
}

/// セルに入力する文字列の決まり（Excel と同じ）
public enum CellInput {
  /// "=" で始まり、続きがあれば数式
  public static func isFormula(_ input: String) -> Bool {
    input.hasPrefix("=") && input.count > 1
  }

  /// 数式でない入力の値。"'" で始めると、数に見えても文字列として扱う
  public static func literal(_ input: String) -> CellValue {
    if input.isEmpty { return .empty }
    if input.hasPrefix("'") { return .text(String(input.dropFirst())) }
    let trimmed = input.trimmingCharacters(in: .whitespaces)
    if let number = number(trimmed) { return .number(number) }
    switch trimmed.uppercased() {
    case "TRUE": return .bool(true)
    case "FALSE": return .bool(false)
    default: break
    }
    if let error = CellError(rawValue: trimmed.uppercased()), error != .circular { return .error(error) }
    return .text(input)
  }

  /// "12" "-3.5" "1e3" "50%" を数にする。"nan" や "inf" は数にしない
  public static func number(_ text: String) -> Double? {
    var text = Substring(text)
    var scale = 1.0
    if text.hasSuffix("%") {
      text = text.dropLast()
      scale = 0.01
    }
    guard !text.isEmpty, text.allSatisfy({ "0123456789.+-eE".contains($0) }),
      let number = Double(text), number.isFinite
    else { return nil }
    return number * scale
  }

  /// 文字列をそのまま文字列として入れるときの入力。数や数式に見えるなら "'" を付ける
  public static func text(_ text: String) -> String {
    if text.hasPrefix("=") || text.hasPrefix("'") || literal(text) != .text(text) { return "'" + text }
    return text
  }

  /// 数を入れるときの入力。1.0 は "1"、0.1 は "0.1"（最短で元の数に戻る表記）
  public static func number(_ number: Double) -> String {
    if number == number.rounded(), abs(number) < 1e15 { return String(Int64(number)) }
    return "\(number)"
  }

  public static func bool(_ bool: Bool) -> String {
    bool ? "TRUE" : "FALSE"
  }
}
