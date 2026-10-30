import Foundation

/// Excel の .xlsx（Office Open XML）を読み書きする。
/// 読むときは値と数式だけを取り出し、書式・グラフ・マクロなどは捨てる
public enum XLSX {
  /// Excel 自体にシート数の上限はないが、ふつうの使い方で数百枚にはならない
  static let maxSheets = 255

  /// .xlsx を読む。数式は "=" + 式 の入力にし、キャッシュされた値は使わない（Kinko 側で計算し直す）
  public static func read(_ data: Data) throws -> Workbook {
    // .xls と、パスワード付きの .xlsx はどちらも OLE2（複合ファイル）形式で、先頭の 8 バイトが同じ
    if data.starts(with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) {
      // 暗号化された .xlsx は中に "EncryptedPackage" という名前（UTF-16）のストリームを持つ
      let marker = Data("EncryptedPackage".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
      throw data.range(of: marker) == nil ? SpreadsheetFileError.legacyExcel : .encryptedExcel
    }
    let zip: ZipArchive
    do {
      zip = try ZipArchive(data)
    } catch SpreadsheetFileError.notZip {
      throw SpreadsheetFileError.notXLSX
    }
    return try XLSXReader(zip: zip).read()
  }

  /// values(sheetIndex, address) は数式セルの計算結果（キャッシュ値として <v> に書く）
  public static func write(_ workbook: Workbook, values: (Int, CellAddress) -> CellValue) throws -> Data {
    let names = sheetNames(workbook.sheets.map(\.name))
    let header = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"# + "\n"
    let relationshipNS = "http://schemas.openxmlformats.org/package/2006/relationships"
    let typeBase = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
    let contentBase = "application/vnd.openxmlformats-officedocument.spreadsheetml."

    var contentTypes = header + #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">"#
    contentTypes += #"<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>"#
    contentTypes += #"<Default Extension="xml" ContentType="application/xml"/>"#
    contentTypes += #"<Override PartName="/xl/workbook.xml" ContentType="\#(contentBase)sheet.main+xml"/>"#
    contentTypes += #"<Override PartName="/xl/styles.xml" ContentType="\#(contentBase)styles+xml"/>"#
    var workbookXML = header + #"<workbook xmlns="\#(mainNamespace)" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>"#
    var workbookRels = header + #"<Relationships xmlns="\#(relationshipNS)">"#
    for (index, name) in names.enumerated() {
      let number = index + 1
      contentTypes += #"<Override PartName="/xl/worksheets/sheet\#(number).xml" ContentType="\#(contentBase)worksheet+xml"/>"#
      workbookXML += #"<sheet name="\#(escape(name))" sheetId="\#(number)" r:id="rId\#(number)"/>"#
      workbookRels += #"<Relationship Id="rId\#(number)" Type="\#(typeBase)worksheet" Target="worksheets/sheet\#(number).xml"/>"#
    }
    contentTypes += "</Types>"
    // fullCalcOnLoad: 開いたときに Excel や Numbers に全部計算し直させる（キャッシュ値が古くても困らないように）
    workbookXML += #"</sheets><calcPr fullCalcOnLoad="1"/></workbook>"#
    workbookRels += #"<Relationship Id="rId\#(names.count + 1)" Type="\#(typeBase)styles" Target="styles.xml"/></Relationships>"#
    let rootRels =
      header + #"<Relationships xmlns="\#(relationshipNS)">"#
      + #"<Relationship Id="rId1" Type="\#(typeBase)officeDocument" Target="xl/workbook.xml"/></Relationships>"#
    // シートを書きながら、使われた書式を集める（styles.xml はそのあとで書く）
    var styles = StyleTable()
    var sheetFiles: [(name: String, data: Data)] = []
    for (index, sheet) in workbook.sheets.enumerated() {
      let xml = try header + worksheetXML(sheet, styles: &styles) { values(index, $0) }
      sheetFiles.append(("xl/worksheets/sheet\(index + 1).xml", Data(xml.utf8)))
    }

    // docProps（作成者・作成日時など）はわざと書かない。書き出したファイルから誰がいつ作ったかが漏れないように
    let files: [(name: String, data: Data)] = [
      ("[Content_Types].xml", Data(contentTypes.utf8)),
      ("_rels/.rels", Data(rootRels.utf8)),
      ("xl/workbook.xml", Data(workbookXML.utf8)),
      ("xl/_rels/workbook.xml.rels", Data(workbookRels.utf8)),
      ("xl/styles.xml", Data((header + styles.xml).utf8)),
    ]
    return try ZipWriter.archive(files + sheetFiles)
  }

  static let mainNamespace = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"

  /// 行の高さ（ポイント）の範囲。409 は Excel の上限。2 より低い行は、読むときに見えないほど細くならないよう 2 にする
  static let minRowHeight = 2.0
  static let maxRowHeight = 409.0

  private static func worksheetXML(
    _ sheet: Sheet, styles: inout StyleTable, values: (CellAddress) -> CellValue
  ) throws -> String {
    var xml = #"<worksheet xmlns="\#(mainNamespace)">"#
    let widths = sheet.columnWidths.filter { $0.value.isFinite && $0.value > 0 }.sorted { $0.key < $1.key }
    if !widths.isEmpty {
      xml += "<cols>"
      for (column, points) in widths {
        // Kinko のポイントを Excel の「文字数」の幅に戻す（読むときの逆）
        let width = max(0, (points - 5) / 7)
        xml += #"<col min="\#(column + 1)" max="\#(column + 1)" width="\#(width)" customWidth="1"/>"#
      }
      xml += "</cols>"
    }
    xml += "<sheetData>"
    // 値のないセルも、書式があれば書く（背景色や罫線を残すため）
    let rows = Dictionary(grouping: Set(sheet.cells.keys).union(sheet.styles.keys), by: \.row)
    let heights = sheet.rowHeights.filter { (0..<CellAddress.maxRows).contains($0.key) && $0.value.isFinite && $0.value > 0 }
    // 手で高さを決めた行は、セルがなくても空の <row> として書く（行の順に並べる）
    for row in Set(rows.keys).union(heights.keys).sorted() {
      xml += #"<row r="\#(row + 1)""#
      if let height = heights[row] {
        xml += #" ht="\#(min(height, maxRowHeight))" customHeight="1""#
      }
      guard let addresses = rows[row] else {
        xml += "/>"
        continue
      }
      xml += ">"
      for address in addresses.sorted() {
        let style = try styles.index(of: sheet[style: address])
        xml += cellXML(address, input: sheet[address], style: style, values: values)
      }
      xml += "</row>"
    }
    return xml + "</sheetData></worksheet>"
  }

  private static func cellXML(
    _ address: CellAddress, input: String, style: Int, values: (CellAddress) -> CellValue
  ) -> String {
    let ref = #"r="\#(address)""# + (style == 0 ? "" : #" s="\#(style)""#)
    func cell(_ type: String?, _ content: String) -> String {
      "<c \(ref)\(type.map { #" t="\#($0)""# } ?? "")>\(content)</c>"
    }
    if CellInput.isFormula(input) {
      let formula = "<f>" + escape(addFunctionPrefixes(String(input.dropFirst()))) + "</f>"
      switch values(address) {
      // 循環参照（#CIRC!）は Excel にないエラーなので、キャッシュ値なしにする（開いたときに計算し直される）
      case .empty, .error(.circular): return cell(nil, formula)
      case .number(let number):
        return number.isFinite ? cell(nil, formula + "<v>\(CellInput.number(number))</v>") : cell("e", formula + "<v>#NUM!</v>")
      case .text(let text): return cell("str", formula + "<v>\(escapeText(text))</v>")
      case .bool(let bool): return cell("b", formula + "<v>\(bool ? 1 : 0)</v>")
      case .error(let error): return cell("e", formula + "<v>\(escape(error.rawValue))</v>")
      }
    }
    // 数式でない入力は、Kinko が読むのと同じ決まり（CellInput.literal）で型を決める。"'123" は文字列の "123"
    switch CellInput.literal(input) {
    case .empty: return style == 0 ? "" : "<c \(ref)/>"
    case .number(let number): return cell(nil, "<v>\(CellInput.number(number))</v>")
    case .text(let text): return cell("inlineStr", #"<is><t xml:space="preserve">\#(escapeText(text))</t></is>"#)
    case .bool(let bool): return cell("b", "<v>\(bool ? 1 : 0)</v>")
    case .error(let error): return cell("e", "<v>\(escape(error.rawValue))</v>")
    }
  }
}
