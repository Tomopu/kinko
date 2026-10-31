import Foundation

extension XLSX {
  /// 書式の組み合わせ（cellXfs）や、フォント・塗り・罫線の数の上限。Excel 自体の上限（64,000）に合わせる
  static let maxStyles = 64_000

  /// color 要素の theme="n" が指すテーマの色の順。テーマの XML（dk1, lt1, dk2, lt2 …）とは、最初の 2 組が入れ替わっている
  static let themeSlots = [
    "lt1", "dk1", "lt2", "dk2", "accent1", "accent2", "accent3", "accent4", "accent5", "accent6", "hlink", "folHlink",
  ]

  /// テーマの部品がないときに使う色。Office 2013〜2021 の既定のテーマ「Office」
  /// （Excel 2024 以降の新しい既定テーマのファイルは、テーマの部品を必ず持っているのでそちらを読む）
  static let defaultThemeColors: [CellColor] = [
    "FFFFFF", "000000", "E7E6E6", "44546A", "4472C4", "ED7D31", "A5A5A5", "FFC000", "5B9BD5", "70AD47", "0563C1", "954F72",
  ].map { CellColor(hex: $0)! }

  /// indexed="n" の色。Excel 97 から変わらない 64 色（0〜7 は 8〜15 と同じ）。64 と 65 はシステムの文字色・背景色
  static let indexedColors: [CellColor] = [
    "000000", "FFFFFF", "FF0000", "00FF00", "0000FF", "FFFF00", "FF00FF", "00FFFF",
    "000000", "FFFFFF", "FF0000", "00FF00", "0000FF", "FFFF00", "FF00FF", "00FFFF",
    "800000", "008000", "000080", "808000", "800080", "008080", "C0C0C0", "808080",
    "9999FF", "993366", "FFFFCC", "CCFFFF", "660066", "FF8080", "0066CC", "CCCCFF",
    "000080", "FF00FF", "FFFF00", "00FFFF", "800080", "800000", "008080", "0000FF",
    "00CCFF", "CCFFFF", "CCFFCC", "FFFF99", "99CCFF", "FF99CC", "CC99FF", "FFCC99",
    "3366FF", "33CCCC", "99CC00", "FFCC00", "FF9900", "FF6600", "666699", "969696",
    "003366", "339966", "003300", "333300", "993300", "993366", "333399", "333333",
  ].map { CellColor(hex: $0)! }

  /// テーマの色の明るさを変える（「アクセント 1、白 + 基本色 80%」のような色）。
  /// Excel と同じく HSL の明度だけを動かす: tint < 0 なら黒へ、tint > 0 なら白へ寄せる
  static func tinted(_ color: CellColor, by tint: Double) -> CellColor {
    guard tint.isFinite, tint != 0 else { return color }
    let tint = min(max(tint, -1), 1)
    let red = Double(color.red) / 255, green = Double(color.green) / 255, blue = Double(color.blue) / 255
    let high = max(red, green, blue), low = min(red, green, blue)
    var hue = 0.0, saturation = 0.0
    var lightness = (high + low) / 2
    if high != low {
      let delta = high - low
      saturation = lightness > 0.5 ? delta / (2 - high - low) : delta / (high + low)
      switch high {
      case red: hue = (green - blue) / delta + (green < blue ? 6 : 0)
      case green: hue = (blue - red) / delta + 2
      default: hue = (red - green) / delta + 4
      }
      hue /= 6
    }
    lightness = tint < 0 ? lightness * (1 + tint) : lightness * (1 - tint) + tint

    func channel(_ p: Double, _ q: Double, _ t: Double) -> Double {
      let t = t < 0 ? t + 1 : t > 1 ? t - 1 : t
      if t < 1 / 6 { return p + (q - p) * 6 * t }
      if t < 1 / 2 { return q }
      if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
      return p
    }
    func byte(_ value: Double) -> UInt8 { UInt8(min(max((value * 255).rounded(), 0), 255)) }
    guard saturation > 0 else { return CellColor(red: byte(lightness), green: byte(lightness), blue: byte(lightness)) }
    let q = lightness < 0.5 ? lightness * (1 + saturation) : lightness + saturation - lightness * saturation
    let p = 2 * lightness - q
    return CellColor(
      red: byte(channel(p, q, hue + 1 / 3)), green: byte(channel(p, q, hue)), blue: byte(channel(p, q, hue - 1 / 3)))
  }

  /// 組み込みの表示形式の番号を Kinko の表示形式にする。日付・指数・分数などは標準
  static func builtInNumberFormat(_ id: Int) -> NumberFormat {
    switch id {
    case 1: .number(decimals: 0, grouping: false)  // 0
    case 2: .number(decimals: 2, grouping: false)  // 0.00
    case 3, 37, 38, 41: .number(decimals: 0, grouping: true)  // #,##0（37〜41 は通貨記号のない会計形式）
    case 4, 39, 40, 43: .number(decimals: 2, grouping: true)  // #,##0.00
    // 5〜8 は日本語版では "¥#,##0" などの通貨、42・44 は通貨記号付きの会計形式
    case 5, 6, 42: .currency(decimals: 0)
    case 7, 8, 44: .currency(decimals: 2)
    case 9: .percent(decimals: 0)  // 0%
    case 10: .percent(decimals: 2)  // 0.00%
    default: .general
    }
  }

  /// ユーザー定義の表示形式を Kinko の表示形式にする。正の数の部分（";" の前）だけを見る。
  /// 円記号（"¥" や [$¥-411]）があれば通貨、"%" があれば百分率、"#,##0" ならカンマ区切り、"." の後の 0 や # の数が小数の桁。
  /// ドルなどほかの通貨は、¥ と表示すると意味が変わるので、カンマ区切りの数として読む
  static func numberFormat(formatCode: String) -> NumberFormat {
    let characters = Array(formatCode)
    var plain: [Character] = []
    var currency = false
    let yen: Set<Character> = ["¥", "￥"]
    var index = 0
    scan: while index < characters.count {
      let character = characters[index]
      switch character {
      case ";": break scan
      case "\"":
        index += 1
        while index < characters.count, characters[index] != "\"" {
          if yen.contains(characters[index]) { currency = true }
          index += 1
        }
      case "\\":
        if index + 1 < characters.count, yen.contains(characters[index + 1]) { currency = true }
        index += 1
      case "_", "*": index += 1  // 次の 1 文字は幅合わせ・繰り返しの文字
      case "[":
        var end = index + 1
        while end < characters.count, characters[end] != "]" { end += 1 }
        // [$¥-411] は通貨記号と言語の指定。[Red] や [>=100] は表示形式としては無視する
        let inside = characters[min(index + 1, characters.count)..<min(end, characters.count)]
        if inside.first == "$", inside.contains(where: { yen.contains($0) }) { currency = true }
        index = end
      default:
        if yen.contains(character) { currency = true } else { plain.append(character) }
      }
      index += 1
    }
    let text = String(plain)
    let placeholders: Set<Character> = ["0", "#", "?"]
    // 指数（0.00E+00）と分数（# ?/?）は Kinko にないので標準にする。"General" と "@"（文字列）も標準
    guard text.contains(where: { placeholders.contains($0) }), !text.uppercased().contains("E+"),
      !text.uppercased().contains("E-"), !text.contains("/"), !text.localizedCaseInsensitiveContains("general")
    else { return .general }
    let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    let integerPart = parts[0]
    // "#,##0" のように桁の記号の間にある "," がカンマ区切り。"0," のように末尾にあるのは千で割る指定なので区切りではない
    let grouping = integerPart.firstIndex(of: ",").map { integerPart[$0...].contains(where: { placeholders.contains($0) }) } ?? false
    let decimals = parts.count > 1 ? min(parts[1].prefix(while: { placeholders.contains($0) }).count, 10) : 0
    if text.contains("%") { return .percent(decimals: decimals) }
    if currency { return .currency(decimals: decimals) }
    return .number(decimals: decimals, grouping: grouping)
  }

  /// 書くときの styles.xml。使われた書式だけを、重複をまとめて番号を振る。
  /// 0 番（フォント・罫線・書式）と 0〜1 番（塗り: none と gray125）は Excel が既定として決めているもの
  struct StyleTable {
    /// XML の断片を重複なく並べる
    private struct Interned {
      private(set) var items: [String]
      private var indexes: [String: Int]
      init(_ items: [String]) {
        self.items = items
        indexes = Dictionary(items.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
      }
      mutating func index(of item: String) -> Int {
        if let index = indexes[item] { return index }
        items.append(item)
        indexes[item] = items.count - 1
        return items.count - 1
      }
    }

    private var fonts = Interned([font(CellStyle())])
    private var fills = Interned([
      #"<fill><patternFill patternType="none"/></fill>"#, #"<fill><patternFill patternType="gray125"/></fill>"#,
    ])
    private var borders = Interned([border(CellBorders())])
    /// ユーザー定義の表示形式（番号は 164 から）
    private var numberFormats = Interned([])
    private var formats = Interned([#"<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>"#])
    private var indexes: [CellStyle: Int] = [CellStyle(): 0]

    /// セルの s 属性に書く番号
    mutating func index(of style: CellStyle) throws -> Int {
      if let index = indexes[style] { return index }
      let fontID = fonts.index(of: Self.font(style))
      let fillID = style.fillColor.map { color in
        fills.index(
          of: #"<fill><patternFill patternType="solid"><fgColor rgb="FF\#(color)"/><bgColor indexed="64"/></patternFill></fill>"#)
      } ?? 0
      let borderID = borders.index(of: Self.border(style.borders))
      let formatID = numberFormatID(style.numberFormat)
      var xml = #"<xf numFmtId="\#(formatID)" fontId="\#(fontID)" fillId="\#(fillID)" borderId="\#(borderID)" xfId="0""#
      // apply… は「この書式で既定を上書きする」という印。付けないと一部のアプリが書式を無視する
      if formatID != 0 { xml += #" applyNumberFormat="1""# }
      if fontID != 0 { xml += #" applyFont="1""# }
      if fillID != 0 { xml += #" applyFill="1""# }
      if borderID != 0 { xml += #" applyBorder="1""# }
      var alignment = ""
      if let horizontal = style.alignment { alignment += #" horizontal="\#(horizontal.rawValue)""# }
      if let vertical = style.verticalAlignment { alignment += #" vertical="\#(vertical.rawValue)""# }
      if style.wraps { alignment += #" wrapText="1""# }
      xml += alignment.isEmpty ? "/>" : #" applyAlignment="1"><alignment\#(alignment)/></xf>"#
      let index = formats.index(of: xml)
      guard index < maxStyles else { throw SpreadsheetFileError.tooManyStyles(limit: maxStyles) }
      indexes[style] = index
      return index
    }

    /// 組み込みの番号があればそれを、なければユーザー定義として番号を振る
    private mutating func numberFormatID(_ format: NumberFormat) -> Int {
      let decimals = format.decimals > 0 ? "." + String(repeating: "0", count: format.decimals) : ""
      let code: String
      switch format {
      case .general: return 0
      case .number(0, false): return 1
      case .number(2, false): return 2
      case .number(0, true): return 3
      case .number(2, true): return 4
      case .percent(0): return 9
      case .percent(2): return 10
      case .number(_, let grouping): code = (grouping ? "#,##0" : "0") + decimals
      case .percent: code = "0" + decimals + "%"
      // 組み込みの 5〜8 番は言語によって通貨記号が変わるので使わない。[$¥-411] は「日本語の ¥」の意味で、どの言語の Excel でも ¥ になる
      case .currency: code = "[$¥-411]#,##0" + decimals
      }
      return 164 + numberFormats.index(of: code)
    }

    private static func font(_ style: CellStyle) -> String {
      var xml = "<font>"
      if style.bold { xml += "<b/>" }
      if style.italic { xml += "<i/>" }
      if style.strikethrough { xml += "<strike/>" }
      if style.underline { xml += "<u/>" }
      let size = style.fontSize ?? CellStyle.defaultFontSize
      // 11.0 ではなく 11 と書く（Excel と同じ）
      xml += #"<sz val="\#(size == size.rounded() ? String(Int(size)) : String(size))"/>"#
      if let color = style.textColor { xml += #"<color rgb="FF\#(color)"/>"# }
      return xml + #"<name val="\#(XLSX.escape(style.fontName ?? "Calibri"))"/></font>"#
    }

    /// 辺の順（left, right, top, bottom, diagonal）はスキーマで決まっている。
    /// 色が自動（nil）の線は、Excel 自身と同じく indexed="64"（システムの文字色）と書く
    private static func border(_ borders: CellBorders) -> String {
      var xml = "<border>"
      for (line, name) in [(borders.left, "left"), (borders.right, "right"), (borders.top, "top"), (borders.bottom, "bottom")] {
        guard let line else {
          xml += "<\(name)/>"
          continue
        }
        let color = line.color.map { #"<color rgb="FF\#($0)"/>"# } ?? #"<color indexed="64"/>"#
        xml += #"<\#(name) style="\#(line.style.rawValue)">\#(color)</\#(name)>"#
      }
      return xml + "<diagonal/></border>"
    }

    var xml: String {
      var xml = #"<styleSheet xmlns="\#(XLSX.mainNamespace)">"#
      if !numberFormats.items.isEmpty {
        xml += #"<numFmts count="\#(numberFormats.items.count)">"#
        for (index, code) in numberFormats.items.enumerated() {
          xml += #"<numFmt numFmtId="\#(164 + index)" formatCode="\#(XLSX.escape(code))"/>"#
        }
        xml += "</numFmts>"
      }
      xml += #"<fonts count="\#(fonts.items.count)">"# + fonts.items.joined() + "</fonts>"
      xml += #"<fills count="\#(fills.items.count)">"# + fills.items.joined() + "</fills>"
      xml += #"<borders count="\#(borders.items.count)">"# + borders.items.joined() + "</borders>"
      xml += #"<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>"#
      xml += #"<cellXfs count="\#(formats.items.count)">"# + formats.items.joined() + "</cellXfs>"
      return xml + #"<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>"#
    }
  }
}
