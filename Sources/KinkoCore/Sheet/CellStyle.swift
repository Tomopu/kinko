import Foundation

/// セルの書式。Excel の書式のうち、よく使うものだけ
public struct CellStyle: Codable, Hashable, Sendable {
  public var bold = false
  public var italic = false
  public var underline = false
  public var strikethrough = false
  /// nil なら既定の色（ライト・ダークモードに合わせる）
  public var textColor: CellColor?
  public var fillColor: CellColor?
  /// nil なら「標準」（数は右、文字は左、真偽値とエラーは中央）
  public var alignment: HorizontalAlignment?
  /// nil なら下揃え（Excel の既定）
  public var verticalAlignment: VerticalAlignment?
  /// 列の幅で折り返して、複数行で表示する。行の高さは中身に合わせて自動で高くなる
  public var wraps = false
  /// 折り返さない文字を、右隣が空でもはみ出させずセルの幅で切る（Google スプレッドシートの「切り詰める」）。
  /// Excel にはない指定なので、.xlsx には書かない
  public var clips = false
  public var numberFormat: NumberFormat = .general
  /// 罫線。辺ごとに線の種類と色を持つ
  public var borders = CellBorders()
  /// フォントの種類（ファミリー名。"Hiragino Sans" など）。nil なら既定のフォント
  public var fontName: String?
  /// 文字の大きさ（ポイント。Excel と同じ数え方）。nil なら既定の 11
  public var fontSize: Double?

  /// Excel の既定の文字の大きさ
  public static let defaultFontSize = 11.0
  /// 選べる文字の大きさの範囲（Excel と同じ）
  public static let fontSizes = 1.0...409.0

  public init() {}

  public var isDefault: Bool { self == CellStyle() }

  private enum CodingKeys: String, CodingKey {
    case bold, italic, underline, strikethrough, textColor, fillColor, alignment, verticalAlignment, wraps, numberFormat, borders
    case fontName, fontSize, clips
  }

  /// 既定の値は書かない（JSON を小さく、読みやすくする）
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    if bold { try container.encode(bold, forKey: .bold) }
    if italic { try container.encode(italic, forKey: .italic) }
    if underline { try container.encode(underline, forKey: .underline) }
    if strikethrough { try container.encode(strikethrough, forKey: .strikethrough) }
    try container.encodeIfPresent(textColor, forKey: .textColor)
    try container.encodeIfPresent(fillColor, forKey: .fillColor)
    try container.encodeIfPresent(alignment, forKey: .alignment)
    try container.encodeIfPresent(verticalAlignment, forKey: .verticalAlignment)
    if wraps { try container.encode(wraps, forKey: .wraps) }
    if clips { try container.encode(clips, forKey: .clips) }
    if numberFormat != .general { try container.encode(numberFormat, forKey: .numberFormat) }
    if !borders.isEmpty { try container.encode(borders, forKey: .borders) }
    try container.encodeIfPresent(fontName, forKey: .fontName)
    try container.encodeIfPresent(fontSize, forKey: .fontSize)
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    bold = try container.decodeIfPresent(Bool.self, forKey: .bold) ?? false
    italic = try container.decodeIfPresent(Bool.self, forKey: .italic) ?? false
    underline = try container.decodeIfPresent(Bool.self, forKey: .underline) ?? false
    strikethrough = try container.decodeIfPresent(Bool.self, forKey: .strikethrough) ?? false
    textColor = try container.decodeIfPresent(CellColor.self, forKey: .textColor)
    fillColor = try container.decodeIfPresent(CellColor.self, forKey: .fillColor)
    alignment = try container.decodeIfPresent(HorizontalAlignment.self, forKey: .alignment)
    verticalAlignment = try container.decodeIfPresent(VerticalAlignment.self, forKey: .verticalAlignment)
    wraps = try container.decodeIfPresent(Bool.self, forKey: .wraps) ?? false
    clips = try container.decodeIfPresent(Bool.self, forKey: .clips) ?? false
    numberFormat = try container.decodeIfPresent(NumberFormat.self, forKey: .numberFormat) ?? .general
    borders = try container.decodeIfPresent(CellBorders.self, forKey: .borders) ?? CellBorders()
    fontName = try container.decodeIfPresent(String.self, forKey: .fontName)
    fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize)
  }
}

/// 色。"RRGGBB" の 16 進の文字列として保存する
public struct CellColor: Codable, Hashable, Sendable, CustomStringConvertible {
  public var red: UInt8
  public var green: UInt8
  public var blue: UInt8

  public init(red: UInt8, green: UInt8, blue: UInt8) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  /// "FF0000" や "#ff0000"、Excel の "FFFF0000"（先頭 2 桁は透明度）から作る
  public init?(hex: String) {
    var text = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    if text.count == 8 { text = String(text.dropFirst(2)) }
    guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
    self.init(red: UInt8(value >> 16 & 0xFF), green: UInt8(value >> 8 & 0xFF), blue: UInt8(value & 0xFF))
  }

  /// "FF0000"
  public var description: String { String(format: "%02X%02X%02X", red, green, blue) }

  public init(from decoder: Decoder) throws {
    let text = try decoder.singleValueContainer().decode(String.self)
    guard let color = CellColor(hex: text) else {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "色が不正です: \(text)"))
    }
    self = color
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(description)
  }
}

public enum HorizontalAlignment: String, Codable, Sendable, CaseIterable {
  case left, center, right
}

public enum VerticalAlignment: String, Codable, Sendable, CaseIterable {
  case top, center, bottom
}

/// 辺の組み合わせ（どの辺に罫線を引くかを指定するときに使う）
public struct BorderEdges: OptionSet, Codable, Hashable, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }

  public static let top = BorderEdges(rawValue: 1)
  public static let left = BorderEdges(rawValue: 2)
  public static let bottom = BorderEdges(rawValue: 4)
  public static let right = BorderEdges(rawValue: 8)
  public static let all: BorderEdges = [.top, .left, .bottom, .right]
}

/// 罫線の種類。Excel と同じ 13 種類（名前も .xlsx の style 属性と同じ）
public enum BorderStyle: String, Codable, Sendable, CaseIterable {
  case hair, thin, dotted, dashed, dashDot, dashDotDot, slantDashDot
  case medium, mediumDashed, mediumDashDot, mediumDashDotDot
  case thick, double
}

/// 1 本の罫線
public struct BorderLine: Codable, Hashable, Sendable {
  public var style: BorderStyle
  /// nil なら自動（黒。ダークモードでは白）
  public var color: CellColor?

  public init(style: BorderStyle = .thin, color: CellColor? = nil) {
    self.style = style
    self.color = color
  }

  public static let thin = BorderLine()
}

/// セルの四辺の罫線。引いていない辺は nil
public struct CellBorders: Codable, Hashable, Sendable {
  public var top: BorderLine?
  public var left: BorderLine?
  public var bottom: BorderLine?
  public var right: BorderLine?

  public init(top: BorderLine? = nil, left: BorderLine? = nil, bottom: BorderLine? = nil, right: BorderLine? = nil) {
    self.top = top
    self.left = left
    self.bottom = bottom
    self.right = right
  }

  /// edges の辺すべてに同じ線を引く
  public init(edges: BorderEdges, line: BorderLine = .thin) {
    self.init()
    for edge in [BorderEdges.top, .left, .bottom, .right] where edges.contains(edge) { self[edge] = line }
  }

  public var isEmpty: Bool { top == nil && left == nil && bottom == nil && right == nil }

  /// 線のある辺
  public var edges: BorderEdges {
    var edges: BorderEdges = []
    if top != nil { edges.insert(.top) }
    if left != nil { edges.insert(.left) }
    if bottom != nil { edges.insert(.bottom) }
    if right != nil { edges.insert(.right) }
    return edges
  }

  /// 1 つの辺（.top など）の線。複数の辺を渡したときは最初に見つかった辺
  public subscript(edge: BorderEdges) -> BorderLine? {
    get {
      if edge.contains(.top) { return top }
      if edge.contains(.left) { return left }
      if edge.contains(.bottom) { return bottom }
      return right
    }
    set {
      if edge.contains(.top) { top = newValue }
      if edge.contains(.left) { left = newValue }
      if edge.contains(.bottom) { bottom = newValue }
      if edge.contains(.right) { right = newValue }
    }
  }

  private enum CodingKeys: String, CodingKey {
    case top, left, bottom, right
  }

  /// 形式 3・4 の金庫では、細い実線を引く辺だけを数（BorderEdges）で持っていたので、それも読む
  public init(from decoder: Decoder) throws {
    if let legacy = try? decoder.singleValueContainer().decode(Int.self) {
      self.init(edges: BorderEdges(rawValue: legacy))
      return
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      top: try container.decodeIfPresent(BorderLine.self, forKey: .top),
      left: try container.decodeIfPresent(BorderLine.self, forKey: .left),
      bottom: try container.decodeIfPresent(BorderLine.self, forKey: .bottom),
      right: try container.decodeIfPresent(BorderLine.self, forKey: .right))
  }
}
