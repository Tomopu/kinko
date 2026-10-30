import Foundation

/// セルの位置。行・列とも 0 始まり（A1 は row 0, column 0）
public struct CellAddress: Hashable, Comparable, Sendable, CustomStringConvertible {
  /// Excel と同じ上限（1,048,576 行 × 16,384 列 = XFD 列まで）
  public static let maxRows = 1_048_576
  public static let maxColumns = 16_384

  public var row: Int
  public var column: Int

  public init(row: Int, column: Int) {
    self.row = row
    self.column = column
  }

  /// "A1" や "xfd1048576" から作る（$ は付けない）。形が違うか範囲の外なら nil
  public init?(_ a1: some StringProtocol) {
    let letters = a1.prefix { $0.isASCII && $0.isLetter }
    let digits = a1.dropFirst(letters.count)
    guard !digits.isEmpty, digits.first != "0", digits.allSatisfy({ $0.isASCII && $0.isNumber }),
      let column = Self.columnIndex(letters), let row = Int(digits), row <= Self.maxRows
    else { return nil }
    self.init(row: row - 1, column: column)
  }

  public var description: String { Self.columnName(column) + String(row + 1) }

  public var isValid: Bool { (0..<Self.maxRows).contains(row) && (0..<Self.maxColumns).contains(column) }

  /// 0 → "A"、25 → "Z"、26 → "AA"
  public static func columnName(_ column: Int) -> String {
    var number = column + 1
    var name = ""
    while number > 0 {
      let remainder = (number - 1) % 26
      name.insert(Character(UnicodeScalar(UInt8(65 + remainder))), at: name.startIndex)
      number = (number - 1) / 26
    }
    return name
  }

  /// "A" → 0、"aa" → 26。XFD より先や英字以外なら nil
  public static func columnIndex(_ name: some StringProtocol) -> Int? {
    guard (1...3).contains(name.count) else { return nil }
    var number = 0
    for scalar in name.uppercased().unicodeScalars {
      guard (65...90).contains(scalar.value) else { return nil }
      number = number * 26 + Int(scalar.value - 64)
    }
    return number <= maxColumns ? number - 1 : nil
  }

  /// 行が先、同じ行なら列の順（左上から右へ読む順）
  public static func < (a: CellAddress, b: CellAddress) -> Bool {
    (a.row, a.column) < (b.row, b.column)
  }
}

/// 長方形のセルの範囲。start が左上、end が右下になるようにそろえて持つ
public struct CellRange: Hashable, Sendable, CustomStringConvertible {
  public private(set) var start: CellAddress
  public private(set) var end: CellAddress

  public init(_ a: CellAddress, _ b: CellAddress) {
    start = CellAddress(row: min(a.row, b.row), column: min(a.column, b.column))
    end = CellAddress(row: max(a.row, b.row), column: max(a.column, b.column))
  }

  public init(_ cell: CellAddress) {
    self.init(cell, cell)
  }

  public var rows: ClosedRange<Int> { start.row...end.row }
  public var columns: ClosedRange<Int> { start.column...end.column }
  public var rowCount: Int { end.row - start.row + 1 }
  public var columnCount: Int { end.column - start.column + 1 }

  public func contains(_ cell: CellAddress) -> Bool {
    rows.contains(cell.row) && columns.contains(cell.column)
  }

  public var description: String { start == end ? start.description : "\(start):\(end)" }
}
