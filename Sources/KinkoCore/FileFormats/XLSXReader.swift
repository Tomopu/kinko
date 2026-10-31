import Foundation

/// .xlsx を読む 1 回分の状態
final class XLSXReader {
  private var zip: ZipArchive
  private var sharedStrings: [String] = []
  /// cellXfs の番号（セルの s 属性）ごとの日付の種類
  private var dateStyles: [XLSX.DateStyle?] = []
  /// cellXfs の番号ごとの Kinko の書式
  private var cellStyles: [CellStyle] = []
  /// テーマの色（セルの theme 属性の番号の順）
  private var themeColors = XLSX.defaultThemeColors
  private var date1904 = false
  /// 全シートで読んだ、中身か書式のあるセルの数
  private var cellCount = 0

  init(zip: ZipArchive) {
    self.zip = zip
  }

  func read() throws -> Workbook {
    // ブック本体の場所は _rels/.rels に書いてある（なければ決まった場所）
    let rootRelationships = try relationships(ofPart: "")
    let workbookPath =
      rootRelationships.values.first { $0.type.hasSuffix("/officeDocument") }?.target ?? "xl/workbook.xml"
    guard let workbookData = try zip.read(workbookPath) else { throw SpreadsheetFileError.notXLSX }

    var sheetEntries: [(name: String, id: String)] = []
    var date1904 = false
    try XMLScanner.scan(workbookData, part: workbookPath) { name, attributes, path in
      switch name {
      case "sheet" where path.last == "sheets":
        guard sheetEntries.count < XLSX.maxSheets else { throw SpreadsheetFileError.tooManySheets(limit: XLSX.maxSheets) }
        sheetEntries.append((attributes["name"] ?? "", attributes["id"] ?? ""))
      case "workbookPr":
        date1904 = attributes["date1904"] == "1" || attributes["date1904"] == "true"
      default: break
      }
    }
    self.date1904 = date1904

    let parts = try relationships(ofPart: workbookPath)
    if let path = parts.values.first(where: { $0.type.hasSuffix("/sharedStrings") })?.target,
      let data = try zip.read(path)
    {
      try readSharedStrings(data, part: path)
    }
    // テーマは書式より先に読む（書式の色がテーマの色を指すため）
    if let path = parts.values.first(where: { $0.type.hasSuffix("/theme") })?.target, let data = try zip.read(path) {
      try readTheme(data, part: path)
    }
    if let path = parts.values.first(where: { $0.type.hasSuffix("/styles") })?.target, let data = try zip.read(path) {
      try readStyles(data, part: path)
    }

    var sheets: [Sheet] = []
    for entry in sheetEntries {
      // グラフシートやダイアログシートは表ではないので読まない
      guard let part = parts[entry.id], part.type.hasSuffix("/worksheet") else { continue }
      guard let data = try zip.read(part.target) else { throw SpreadsheetFileError.invalidPart(part.target) }
      sheets.append(try readSheet(data, part: part.target, name: entry.name))
    }
    return Workbook(sheets: sheets)
  }

  /// ある部品の関係ファイル（"xl/workbook.xml" なら "xl/_rels/workbook.xml.rels"）を読み、Id ごとの種類と部品の場所を返す
  private func relationships(ofPart part: String) throws -> [String: (type: String, target: String)] {
    let slash = part.lastIndex(of: "/")
    let directory = slash.map { String(part[...$0]) } ?? ""
    let file = slash.map { String(part[part.index(after: $0)...]) } ?? part
    let path = directory + "_rels/" + file + ".rels"
    guard let data = try zip.read(path) else { return [:] }
    var result: [String: (type: String, target: String)] = [:]
    try XMLScanner.scan(data, part: path) { name, attributes, _ in
      guard name == "Relationship", attributes["TargetMode"] != "External", let id = attributes["Id"],
        let type = attributes["Type"], let target = attributes["Target"]
      else { return }
      result[id] = (type, Self.resolve(target, from: directory))
    }
    return result
  }

  /// 関係ファイルの Target を ZIP の中の名前にする。"/xl/..." は根から、それ以外は元の部品のフォルダーから
  private static func resolve(_ target: String, from directory: String) -> String {
    let target = target.removingPercentEncoding ?? target
    let joined = target.hasPrefix("/") ? target : directory + target
    var components: [Substring] = []
    for component in joined.split(separator: "/") {
      switch component {
      case ".": continue
      case "..": if !components.isEmpty { components.removeLast() }
      default: components.append(component)
      }
    }
    return components.joined(separator: "/")
  }

  private func readSharedStrings(_ data: Data, part: String) throws {
    var strings: [String] = []
    var current = ""
    try XMLScanner.scan(
      data, part: part,
      start: { name, _, _ in
        if name == "si" { current = "" }
      },
      end: { name, text, path in
        switch name {
        // 書式付きの文字列は <r><t>…</t></r> に分かれているのでつなげる。
        // 日本語版 Excel が付けるふりがな（<rPh><t>カナ</t></rPh>）は表示されない情報なので混ぜない
        case "t" where path.contains("si") && !path.contains("rPh"): current += text
        case "si":
          guard strings.count < SpreadsheetLimits.maxCells else {
            throw SpreadsheetFileError.tooManyCells(limit: SpreadsheetLimits.maxCells)
          }
          strings.append(XLSX.unescapeText(current))
        default: break
        }
      })
    sharedStrings = strings
  }

  /// テーマ（xl/theme/theme1.xml）の色を読む。セルの色が theme="4" のように番号で指していることがあるため
  private func readTheme(_ data: Data, part: String) throws {
    var colors: [String: CellColor] = [:]
    try XMLScanner.scan(data, part: part) { name, attributes, path in
      guard path.contains("clrScheme"), let slot = path.last else { return }
      switch name {
      case "srgbClr": if let color = attributes["val"].flatMap(CellColor.init(hex:)) { colors[slot] = color }
      // 黒と白はシステムの色として書かれ、lastClr に実際の色がある
      case "sysClr": if let color = attributes["lastClr"].flatMap(CellColor.init(hex:)) { colors[slot] = color }
      default: break
      }
    }
    themeColors = XLSX.themeSlots.enumerated().map { colors[$1] ?? XLSX.defaultThemeColors[$0] }
  }

  /// styles.xml を読み、cellXfs の番号ごとに Kinko の書式と日付の種類を決める
  private func readStyles(_ data: Data, part: String) throws {
    // 色は最後にまとめて決める（独自のパレット <colors> がファイルの末尾にあるため）。それまでは属性のまま持つ
    typealias ColorSpec = [String: String]
    struct Font {
      var bold = false, italic = false, underline = false, strikethrough = false
      var color: ColorSpec?
      var size: Double?
      var name: String?
    }
    struct Fill {
      var pattern = "none"
      var color: ColorSpec?
    }
    struct Format {
      var numberFormat = 0, font = 0, fill = 0, border = 0
      var alignment: HorizontalAlignment?
      var verticalAlignment: VerticalAlignment?
      var wraps = false
    }
    var customFormats: [Int: String] = [:]
    var fonts: [Font] = []
    var fills: [Fill] = []
    /// 罫線は辺（BorderEdges の rawValue）ごとの線の種類と色
    var borders: [[Int: (style: BorderStyle, color: ColorSpec?)]] = []
    var formats: [Format] = []
    var palette: [CellColor] = []
    let limit = XLSX.maxStyles

    /// path の末尾が [..., grandparent, parent] か（差分書式 dxfs の中の font などと区別する）
    func within(_ path: [String], _ grandparent: String, _ parent: String) -> Bool {
      path.count >= 2 && path[path.count - 1] == parent && path[path.count - 2] == grandparent
    }
    /// 罫線の辺の要素名。start と end は新しい書き方の左と右
    func edge(_ name: String) -> BorderEdges? {
      switch name {
      case "left", "start": .left
      case "right", "end": .right
      case "top": .top
      case "bottom": .bottom
      default: nil
      }
    }
    /// <b/> は太字、<b val="0"/> は太字でない
    func isOn(_ attributes: [String: String]) -> Bool {
      !["0", "false", "none"].contains(attributes["val"] ?? "")
    }

    try XMLScanner.scan(data, part: part) { name, attributes, path in
      // 数が多すぎるファイルは、読み続けずに断る
      guard fonts.count <= limit, fills.count <= limit, borders.count <= limit, formats.count <= limit,
        customFormats.count <= limit, palette.count <= limit
      else { throw SpreadsheetFileError.tooManyStyles(limit: limit) }
      switch name {
      case "numFmt" where path.last == "numFmts":
        if let id = attributes["numFmtId"].flatMap({ Int($0) }) { customFormats[id] = attributes["formatCode"] ?? "" }
      case "font" where path.last == "fonts": fonts.append(Font())
      case "b" where within(path, "fonts", "font"): fonts[fonts.count - 1].bold = isOn(attributes)
      case "i" where within(path, "fonts", "font"): fonts[fonts.count - 1].italic = isOn(attributes)
      // 下線は一重・二重・会計用などがあるが、どれも「下線あり」にする
      case "u" where within(path, "fonts", "font"): fonts[fonts.count - 1].underline = isOn(attributes)
      case "strike" where within(path, "fonts", "font"): fonts[fonts.count - 1].strikethrough = isOn(attributes)
      case "color" where within(path, "fonts", "font"): fonts[fonts.count - 1].color = attributes
      case "sz" where within(path, "fonts", "font"): fonts[fonts.count - 1].size = attributes["val"].flatMap { Double($0) }
      case "name" where within(path, "fonts", "font"): fonts[fonts.count - 1].name = attributes["val"]
      case "fill" where path.last == "fills": fills.append(Fill())
      case "patternFill" where within(path, "fills", "fill"): fills[fills.count - 1].pattern = attributes["patternType"] ?? "none"
      case "fgColor" where path.count >= 3 && path[path.count - 3] == "fills" && path.last == "patternFill":
        fills[fills.count - 1].color = attributes
      case "border" where path.last == "borders": borders.append([:])
      // 線の種類は Excel と同じ 13 種類。知らない種類は細線にする。斜線（diagonal）は Kinko にないので無視する
      case _ where edge(name) != nil && within(path, "borders", "border"):
        guard let style = attributes["style"], style != "none", let edge = edge(name) else { break }
        borders[borders.count - 1][edge.rawValue] = (BorderStyle(rawValue: style) ?? .thin, nil)
      case "color" where path.count >= 3 && path[path.count - 3] == "borders" && path[path.count - 2] == "border":
        if let edge = edge(path[path.count - 1]), borders[borders.count - 1][edge.rawValue] != nil {
          borders[borders.count - 1][edge.rawValue]?.color = attributes
        }
      // cellXfs（セルが使う書式）だけを見る。cellStyleXfs は「スタイル」の定義でセルからは直接使われない
      case "xf" where path.last == "cellXfs":
        func number(_ key: String) -> Int { attributes[key].flatMap { Int($0) } ?? 0 }
        formats.append(
          Format(numberFormat: number("numFmtId"), font: number("fontId"), fill: number("fillId"), border: number("borderId")))
      case "alignment" where within(path, "cellXfs", "xf"):
        formats[formats.count - 1].alignment =
          switch attributes["horizontal"] {
          case "left": .left
          case "center", "centerContinuous": .center
          case "right": .right
          // 標準・繰り返し・両端揃え・均等割り付けは Kinko にないので標準にする
          default: nil
          }
        formats[formats.count - 1].verticalAlignment =
          switch attributes["vertical"] {
          case "top": .top
          // 縦の両端揃え・均等割り付けは、行の中に文字を散らして置くもの。見た目がいちばん近い中央にする
          case "center", "justify", "distributed": .center
          // 下揃え（bottom）は Excel の既定なので、持たない
          default: nil
          }
        formats[formats.count - 1].wraps = ["1", "true"].contains(attributes["wrapText"] ?? "")
      case "rgbColor" where path.last == "indexedColors":
        palette.append(attributes["rgb"].flatMap(CellColor.init(hex:)) ?? CellColor(red: 0, green: 0, blue: 0))
      default: break
      }
    }

    // 独自のパレットがなければ、Excel 97 以来の 64 色を使う
    if palette.isEmpty { palette = XLSX.indexedColors }
    let black = CellColor(red: 0, green: 0, blue: 0)
    func color(_ spec: ColorSpec?) -> CellColor? {
      guard let spec, spec["auto"] != "1", spec["auto"] != "true" else { return nil }
      var base: CellColor?
      if let rgb = spec["rgb"] {
        base = CellColor(hex: rgb)
      } else if let theme = spec["theme"].flatMap({ Int($0) }), themeColors.indices.contains(theme) {
        base = themeColors[theme]
      } else if let index = spec["indexed"].flatMap({ Int($0) }), palette.indices.contains(index) {
        // 64（システムの文字色）と 65（システムの背景色）はパレットの外なので nil（既定の色）になる
        base = palette[index]
      }
      guard let base else { return nil }
      return spec["tint"].flatMap { Double($0) }.map { XLSX.tinted(base, by: $0) } ?? base
    }

    dateStyles = []
    cellStyles = []
    for format in formats {
      let dateStyle = customFormats[format.numberFormat].map { XLSX.dateStyle(formatCode: $0) }
        ?? XLSX.builtInDateStyle(format.numberFormat)
      var style = CellStyle()
      if fonts.indices.contains(format.font) {
        let font = fonts[format.font]
        style.bold = font.bold
        style.italic = font.italic
        style.underline = font.underline
        style.strikethrough = font.strikethrough
        // 黒の文字は「既定の色」として持つ（ダークモードで黒い字が背景に溶けないように）
        style.textColor = color(font.color).flatMap { $0 == black ? nil : $0 }
        // 大きさは 11 以外を、種類はブックの既定（0 番のフォント）と違うものだけを持つ
        if let size = font.size, size.isFinite, size != CellStyle.defaultFontSize {
          style.fontSize = min(max(size, CellStyle.fontSizes.lowerBound), CellStyle.fontSizes.upperBound)
        }
        if let name = font.name, !name.isEmpty, name != fonts[0].name { style.fontName = name }
      }
      if fills.indices.contains(format.fill) {
        let fill = fills[format.fill]
        // gray125 は Excel が予約している 2 番目の塗り（ふつうは使われない）。ほかの模様は前景色の塗りつぶしで近似する
        style.fillColor = ["none", "gray125"].contains(fill.pattern) ? nil : color(fill.color)
      }
      if borders.indices.contains(format.border) {
        for (edge, line) in borders[format.border] {
          // 黒の線は「自動の色」として持つ（ダークモードで背景に溶けないよう、文字色と同じ扱い）
          style.borders[BorderEdges(rawValue: edge)] = BorderLine(
            style: line.style, color: color(line.color).flatMap { $0 == black ? nil : $0 })
        }
      }
      style.alignment = format.alignment
      style.verticalAlignment = format.verticalAlignment
      style.wraps = format.wraps
      // 日付の書式は、値を日付の文字列にするので表示形式としては持たない
      if dateStyle == nil {
        style.numberFormat =
          customFormats[format.numberFormat].map { XLSX.numberFormat(formatCode: $0) }
          ?? XLSX.builtInNumberFormat(format.numberFormat)
      }
      dateStyles.append(dateStyle)
      cellStyles.append(style)
    }
  }

  private func readSheet(_ data: Data, part: String, name: String) throws -> Sheet {
    var cells: [CellAddress: String] = [:]
    var styles: [CellAddress: CellStyle] = [:]
    var widths: [Int: Double] = [:]
    var heights: [Int: Double] = [:]
    var row = -1
    var column = -1
    // 読んでいる途中の <c> の中身
    var address = CellAddress(row: 0, column: 0)
    var type: String?
    var style = 0
    var formulaAttributes: [String: String]?
    var formulaText = ""
    var value: String?
    var inlineText = ""
    /// 共有数式の親（si の番号ごとの、式と親のセルの位置）
    var sharedFormulas: [String: (input: String, address: CellAddress)] = [:]
    let invalid = SpreadsheetFileError.invalidPart(part)

    func cellInput() throws -> String {
      if let formula = formulaAttributes, formula["t"] != "dataTable" {
        // 共有数式: 親は式を持ち、子は si だけを持つ。子は親の式を位置の差だけずらしたもの
        if formula["t"] == "shared", let id = formula["si"] {
          if !formulaText.isEmpty {
            let input = "=" + XLSX.removeFunctionPrefixes(formulaText)
            sharedFormulas[id] = (input, address)
            if !XLSX.hasExternalReference(input) { return input }
          } else if let master = sharedFormulas[id], !XLSX.hasExternalReference(master.input) {
            return Formula.shifted(
              master.input, rowOffset: address.row - master.address.row, columnOffset: address.column - master.address.column)
          }
        } else if !formulaText.isEmpty {
          // 配列数式（t="array"）も、左上のセルのふつうの数式として読む
          let input = "=" + XLSX.removeFunctionPrefixes(formulaText)
          if !XLSX.hasExternalReference(input) { return input }
        }
        // 式が取れなかった（データテーブルなど）ときや、ほかのブックを参照する式は、キャッシュされた値を使う
      }
      switch type {
      case "s":
        guard let index = value.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }), sharedStrings.indices.contains(index)
        else { throw invalid }
        return CellInput.text(sharedStrings[index])
      case "inlineStr": return CellInput.text(XLSX.unescapeText(inlineText))
      case "str", "d": return CellInput.text(XLSX.unescapeText(value ?? ""))
      case "b": return value.map { CellInput.bool($0 == "1" || $0 == "true") } ?? ""
      case "e": return value?.trimmingCharacters(in: .whitespaces) ?? ""
      default:
        guard let text = value?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return "" }
        guard let number = Double(text), number.isFinite else { return CellInput.text(text) }
        // Kinko には表示形式がないので、日付の書式のセルは日付の文字列にする（数のままだと 46325 のように見える）
        if dateStyles.indices.contains(style), let dateStyle = dateStyles[style],
          let date = XLSX.dateText(serial: number, style: dateStyle, date1904: date1904)
        {
          return CellInput.text(date)
        }
        return CellInput.number(number)
      }
    }

    try XMLScanner.scan(
      data, part: part,
      start: { name, attributes, path in
        switch name {
        case "row":
          // r がなければ前の行の次
          if let r = attributes["r"] {
            guard let number = Int(r), (1...CellAddress.maxRows).contains(number) else { throw invalid }
            row = number - 1
          } else {
            row += 1
          }
          column = -1
          // 手で決めた高さ（customHeight）だけを使う。Excel は自動の高さも ht に書くが、
          // それは Excel のフォントで測った値なので、Kinko で測り直せるよう捨てる
          if ["1", "true"].contains(attributes["customHeight"] ?? ""), row < CellAddress.maxRows,
            let height = attributes["ht"].flatMap({ Double($0) }), height.isFinite
          {
            heights[row] = Swift.min(Swift.max(height, XLSX.minRowHeight), XLSX.maxRowHeight)
          }
        case "c":
          // r がなければ同じ行の前のセルの右隣
          if let r = attributes["r"] {
            guard let parsed = CellAddress(r) else { throw invalid }
            address = parsed
          } else {
            address = CellAddress(row: max(row, 0), column: column + 1)
          }
          guard address.isValid else { throw invalid }
          column = address.column
          type = attributes["t"]
          style = attributes["s"].flatMap { Int($0) } ?? 0
          formulaAttributes = nil
          formulaText = ""
          value = nil
          inlineText = ""
        case "f": formulaAttributes = attributes
        case "col" where path.last == "cols":
          // 列の幅は Excel では「標準フォントの数字何文字分」。Kinko のポイントにおおよそ直す（8.43 → 64）
          guard let min = attributes["min"].flatMap({ Int($0) }), let max = attributes["max"].flatMap({ Int($0) }),
            let width = attributes["width"].flatMap({ Double($0) }), width.isFinite,
            min >= 1, min <= max, max <= CellAddress.maxColumns,
            // 列全体の既定の書式を表す min=1 max=16384 のような広い範囲は、幅の指定として使わない
            max - min < 1000
          else { return }
          let points = Swift.min(Swift.max((width * 7 + 5).rounded(), 16), 800)
          for column in (min - 1)...(max - 1) { widths[column] = points }
        default: break
        }
      },
      end: { name, text, path in
        switch name {
        case "f": formulaText = text
        case "v": value = text
        case "t" where path.contains("is") && !path.contains("rPh"): inlineText += text
        case "c":
          let input = try cellInput()
          var cellStyle = self.cellStyles.indices.contains(style) ? self.cellStyles[style] : CellStyle()
          // 表示形式は数（と、これから数を入れるかもしれない空のセル）にだけ意味がある。文字列や真偽値には付けない
          if let type, type != "n" { cellStyle.numberFormat = .general }
          let styled = !cellStyle.isDefault
          // 値がなくても、背景色や罫線だけのセルは書式を残す
          guard !input.isEmpty || styled else { return }
          if cells[address] == nil, styles[address] == nil {
            self.cellCount += 1
            guard self.cellCount <= SpreadsheetLimits.maxCells else {
              throw SpreadsheetFileError.tooManyCells(limit: SpreadsheetLimits.maxCells)
            }
          }
          if !input.isEmpty { cells[address] = input }
          if styled { styles[address] = cellStyle }
        default: break
        }
      })
    var sheet = Sheet(name: name, cells: cells, columnWidths: widths, styles: styles)
    sheet.rowHeights = heights
    return sheet
  }
}
