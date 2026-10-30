import Foundation

/// 表の 1 枚のシート。セルには入力したとおりの文字列（"=SUM(A1:A3)" や "120"）を持ち、計算結果は持たない
public struct Sheet: Equatable, Sendable {
  public static let defaultColumnWidth: Double = 96

  public var name: String
  /// 空でないセルだけを持つ
  public private(set) var cells: [CellAddress: String]
  /// 既定の幅から変えた列だけを持つ（ポイント）
  public var columnWidths: [Int: Double]
  /// 手で高さを決めた行だけを持つ（ポイント）。持たない行は、折り返す文字に合わせて自動で高くなる
  public var rowHeights: [Int: Double] = [:]
  /// 書式を変えたセルだけを持つ。中身が空でも書式（背景色や罫線）だけのセルはある
  public private(set) var styles: [CellAddress: CellStyle]

  public init(
    name: String, cells: [CellAddress: String] = [:], columnWidths: [Int: Double] = [:], styles: [CellAddress: CellStyle] = [:]
  ) {
    self.name = name
    self.cells = cells.filter { !$0.value.isEmpty }
    self.columnWidths = columnWidths
    self.styles = styles.filter { !$0.value.isDefault }
  }

  /// 既定の書式に戻すと、持たなくなる
  public subscript(style address: CellAddress) -> CellStyle {
    get { styles[address] ?? CellStyle() }
    set { styles[address] = newValue.isDefault ? nil : newValue }
  }

  /// 空文字列を入れるとセルを消す
  public subscript(_ address: CellAddress) -> String {
    get { cells[address] ?? "" }
    set { cells[address] = newValue.isEmpty ? nil : newValue }
  }

  /// 中身のあるセルを囲む最小の範囲。空のシートなら nil
  public var usedRange: CellRange? {
    guard let first = cells.keys.first else { return nil }
    var top = first.row, bottom = first.row, left = first.column, right = first.column
    for address in cells.keys {
      top = min(top, address.row)
      bottom = max(bottom, address.row)
      left = min(left, address.column)
      right = max(right, address.column)
    }
    return CellRange(CellAddress(row: top, column: left), CellAddress(row: bottom, column: right))
  }

  public func width(ofColumn column: Int) -> Double {
    columnWidths[column] ?? Self.defaultColumnWidth
  }

  /// 全セルをまとめて置き換える（行の挿入などで位置をずらすとき）
  public mutating func replaceCells(_ cells: [CellAddress: String]) {
    self.cells = cells.filter { !$0.value.isEmpty && $0.key.isValid }
  }

  public mutating func replaceStyles(_ styles: [CellAddress: CellStyle]) {
    self.styles = styles.filter { !$0.value.isDefault && $0.key.isValid }
  }
}

extension Sheet: Codable {
  private enum CodingKeys: String, CodingKey {
    case name, cells, columnWidths, rowHeights, styles
  }

  /// セルの位置は "A1" 形式の文字列をキーにして保存する（読んで分かる形にするため）
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decode(String.self, forKey: .name)
    var cells: [CellAddress: String] = [:]
    for (key, value) in try container.decode([String: String].self, forKey: .cells) {
      guard let address = CellAddress(key) else {
        throw DecodingError.dataCorruptedError(forKey: .cells, in: container, debugDescription: "セルの位置が不正です: \(key)")
      }
      cells[address] = value
    }
    self.cells = cells.filter { !$0.value.isEmpty }
    var widths: [Int: Double] = [:]
    for (key, value) in try container.decodeIfPresent([String: Double].self, forKey: .columnWidths) ?? [:] {
      if let column = CellAddress.columnIndex(key), value.isFinite, value > 0 { widths[column] = value }
    }
    columnWidths = widths
    var heights: [Int: Double] = [:]
    for (key, value) in try container.decodeIfPresent([String: Double].self, forKey: .rowHeights) ?? [:] {
      if let row = Int(key), row >= 1, row <= CellAddress.maxRows, value.isFinite, value > 0 { heights[row - 1] = value }
    }
    rowHeights = heights
    var styles: [CellAddress: CellStyle] = [:]
    for (key, value) in try container.decodeIfPresent([String: CellStyle].self, forKey: .styles) ?? [:] {
      guard let address = CellAddress(key) else {
        throw DecodingError.dataCorruptedError(forKey: .styles, in: container, debugDescription: "セルの位置が不正です: \(key)")
      }
      if !value.isDefault { styles[address] = value }
    }
    self.styles = styles
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(name, forKey: .name)
    try container.encode(Dictionary(uniqueKeysWithValues: cells.map { ($0.key.description, $0.value) }), forKey: .cells)
    try container.encode(
      Dictionary(uniqueKeysWithValues: columnWidths.map { (CellAddress.columnName($0.key), $0.value) }), forKey: .columnWidths)
    if !rowHeights.isEmpty {
      // 行は画面と同じ 1 始まりの番号で書く
      try container.encode(Dictionary(uniqueKeysWithValues: rowHeights.map { (String($0.key + 1), $0.value) }), forKey: .rowHeights)
    }
    if !styles.isEmpty {
      try container.encode(Dictionary(uniqueKeysWithValues: styles.map { ($0.key.description, $0.value) }), forKey: .styles)
    }
  }
}

/// 表のファイル 1 つ。1 枚以上のシートを持つ
public struct Workbook: Codable, Equatable, Sendable {
  public var sheets: [Sheet]

  public init(sheets: [Sheet] = [Sheet(name: "Sheet1")]) {
    self.sheets = sheets.isEmpty ? [Sheet(name: "Sheet1")] : sheets
  }

  /// シート名は Excel と同じく大文字・小文字を区別しない
  public func sheetIndex(named name: String) -> Int? {
    sheets.firstIndex { $0.name.caseInsensitiveCompare(name) == .orderedSame }
  }

  /// "Sheet2" "Sheet3" … のうち、まだ使われていない名前
  public func newSheetName() -> String {
    var number = sheets.count + 1
    while sheetIndex(named: "Sheet\(number)") != nil { number += 1 }
    return "Sheet\(number)"
  }
}
