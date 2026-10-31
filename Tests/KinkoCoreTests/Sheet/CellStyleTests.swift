import Foundation
import Testing

@testable import KinkoCore

@Suite("セルの書式")
struct CellStyleTests {
  /// 果物と値段の表。C 列は B 列を 2 倍する数式で、A2 だけ太字
  private func fruits() -> Workbook {
    var sheet = Sheet(cells: [
      "A1": "みかん", "B1": "300", "C1": "=B1*2",
      "A2": "りんご", "B2": "100", "C2": "=B2*2",
      "A3": "", "B3": "50", "C3": "=B3*2",
      "A4": "バナナ", "B4": "200", "C4": "=B4*2",
    ])
    sheet[style: "A2"] = style { $0.bold = true }
    return Workbook(sheets: [sheet])
  }

  @Test("表示形式に合わせて数を文字列にする", arguments: [
    // 標準は入力どおりに見せるので文字列を作らない
    (NumberFormat.general, 1234.5, nil),
    // 数値は四捨五入し、3 桁ごとのカンマは選べる
    (.number(decimals: 0, grouping: true), 1234567.8, "1,234,568"),
    (.number(decimals: 2, grouping: true), -1234.5, "-1,234.50"),
    (.number(decimals: 2, grouping: false), 2.675, "2.68"),
    (.currency(decimals: 0), -1500, "-¥1,500"),
    (.percent(decimals: 1), 0.125, "12.5%"),
    // 0 に丸まった負の数には - を付けない
    (.number(decimals: 0, grouping: false), -0.4, "0"),
    (.currency(decimals: 0), -0.2, "¥0"),
  ] as [(NumberFormat, Double, String?)])
  func numberFormats(format: NumberFormat, number: Double, expected: String?) {
    // Given / When
    let text = format.format(number)

    // Then
    #expect(text == expected)
  }

  @Test("小数の桁を変えると、標準は数値になり、桁は 0 より減らない")
  func numberFormatDecimals() {
    // Given / When
    let fromGeneral = NumberFormat.general.withDecimals(2)
    let belowZero = NumberFormat.percent(decimals: 1).withDecimals(-1)

    // Then
    #expect(fromGeneral == .number(decimals: 2, grouping: false))
    #expect(belowZero == .percent(decimals: 0))
  }

  @Test("色は 16 進で読み、先頭の # や透明度は無視し、読めないものは nil")
  func colorsParseHex() {
    // Given / When
    let withHash = CellColor(hex: "#FF8000")
    let withAlpha = CellColor(hex: "FF1E90FF")
    let name = CellColor(hex: "red")

    // Then
    #expect(withHash == CellColor(red: 255, green: 128, blue: 0))
    #expect(withAlpha?.description == "1E90FF")
    #expect(name == nil)
  }

  @Test("書式は JSON を経ても変わらず、既定の書式は持たない")
  func stylesSurviveJSON() throws {
    // Given: いろいろな書式を付けた B2 と、既定の書式を入れた C3
    var sheet = Sheet(name: "S")
    sheet[style: "B2"] = style {
      $0.bold = true
      $0.fillColor = color("FFF2CC")
      $0.alignment = .center
      $0.numberFormat = .currency(decimals: 0)
      $0.borders = CellBorders(top: BorderLine(style: .double, color: color("C00000")), bottom: .thin)
      $0.fontName = "Hiragino Mincho ProN"
      $0.fontSize = 10.5
      $0.clips = true
    }
    sheet[style: "C3"] = CellStyle()

    // When
    let decoded = try JSONDecoder().decode(Sheet.self, from: JSONEncoder().encode(sheet))

    // Then
    #expect(sheet.styles.count == 1)
    #expect(decoded == sheet)
  }

  @Test("既定の値は JSON に書かない")
  func defaultsDisappearFromJSON() throws {
    // Given / When
    let json = String(decoding: try JSONEncoder().encode(CellStyle()), as: UTF8.self)

    // Then
    #expect(json == "{}")
  }

  @Test("行を挿入すると書式もずれる")
  func stylesMoveWithInsertedRows() {
    // Given: A2 が太字
    var sheet = Sheet(cells: ["A2": "x"])
    sheet[style: "A2"] = style { $0.bold = true }
    var book = Workbook(sheets: [sheet])

    // When: 先頭に 2 行挿入する
    book.insertRows(at: 0, count: 2, inSheet: 0)

    // Then
    #expect(book.sheets[0][style: "A4"].bold)
    #expect(!book.sheets[0][style: "A2"].bold)
  }

  @Test("行を削除すると、その行の書式も消える")
  func stylesDisappearWithDeletedRows() {
    // Given: A4 が太字
    var sheet = Sheet(cells: ["A4": "x"])
    sheet[style: "A4"] = style { $0.bold = true }
    var book = Workbook(sheets: [sheet])

    // When: 4 行目を削除する
    book.deleteRows(3...3, inSheet: 0)

    // Then
    #expect(book.sheets[0].styles.isEmpty)
  }

  @Test("つまみで広げると書式も複製する")
  func fillCopiesStyles() {
    // Given: 太字の 1
    var sheet = Sheet(cells: ["A1": "1"])
    sheet[style: "A1"] = style { $0.bold = true }

    // When: option を押して下へ 2 つ広げる
    sheet.fill(from: range("A1"), direction: .down, count: 2, incrementsSingleNumbers: true)

    // Then
    #expect(sheet["A3"] == "3")
    #expect(sheet[style: "A3"].bold)
  }

  @Test("並べ替えは書式と数式ごと行を動かし、数式は動いた先の行を指す")
  func sortingMovesWholeRows() {
    // Given
    var book = fruits()

    // When: B 列の昇順に並べ替える
    book.sortRows(range("A1:C4"), by: 1, ascending: true, inSheet: 0)

    // Then
    let sheet = book.sheets[0]
    #expect((1...4).map { sheet["B\($0)"] } == ["50", "100", "200", "300"])
    #expect(sheet["A2"] == "りんご")
    #expect(sheet[style: "A2"].bold)
    #expect(sheet["C1"] == "=B1*2")
  }

  @Test("空のセルは降順でも最後に並ぶ")
  func sortingPutsEmptyCellsLast() {
    // Given: A3 が空
    var book = fruits()

    // When: A 列の降順に並べ替える
    book.sortRows(range("A1:C4"), by: 0, ascending: false, inSheet: 0)

    // Then
    let sheet = book.sheets[0]
    #expect((1...4).map { sheet["A\($0)"] } == ["りんご", "みかん", "バナナ", ""])
  }

  @Test("行の高さは行の挿入についていく")
  func rowHeightsMoveWithInsertedRows() {
    // Given: 3 行目の高さが 40
    var sheet = Sheet(name: "S")
    sheet.rowHeights = [2: 40]
    var book = Workbook(sheets: [sheet])

    // When: 先頭に 1 行挿入する
    book.insertRows(at: 0, count: 1, inSheet: 0)

    // Then
    #expect(book.sheets[0].rowHeights == [3: 40])
  }

  @Test("行を削除すると、その行の高さも消える")
  func rowHeightsDisappearWithDeletedRows() {
    // Given: 4 行目の高さが 40
    var sheet = Sheet(name: "S")
    sheet.rowHeights = [3: 40]
    var book = Workbook(sheets: [sheet])

    // When: 4 行目を削除する
    book.deleteRows(3...3, inSheet: 0)

    // Then
    #expect(book.sheets[0].rowHeights.isEmpty)
  }

  @Test("セルだけをずらすときは、行の高さは動かない")
  func rowHeightsStayWhenShiftingCells() {
    // Given: 6 行目の高さが 30
    var sheet = Sheet(name: "S")
    sheet.rowHeights = [5: 30]
    var book = Workbook(sheets: [sheet])

    // When: A1 にセルを挿入して下へずらす
    book.insertCells(range("A1"), shift: .vertical, inSheet: 0)

    // Then
    #expect(book.sheets[0].rowHeights == [5: 30])
  }

  @Test("行の高さと折り返しは JSON を経ても変わらず、高さは 1 から数えた行番号で書く")
  func rowHeightsSurviveJSON() throws {
    // Given: 3 行目が高さ 40 で、A3 は折り返して上に寄せた 2 行の文字列
    var sheet = Sheet(cells: ["A3": "1 行目\n2 行目"])
    sheet.rowHeights = [2: 40]
    sheet[style: "A3"] = style {
      $0.wraps = true
      $0.verticalAlignment = .top
    }

    // When
    let data = try JSONEncoder().encode(sheet)
    let decoded = try JSONDecoder().decode(Sheet.self, from: data)

    // Then
    #expect(decoded == sheet)
    #expect(String(decoding: data, as: UTF8.self).contains(#""rowHeights":{"3":40}"#))
  }

  @Test("形式 4 までの罫線（細い実線の辺を数で持っていた）も読める")
  func legacyBordersBecomeThinLines() throws {
    // Given / When: 上と下の辺を表す 5
    let style = try JSONDecoder().decode(CellStyle.self, from: Data(#"{"borders":5}"#.utf8))

    // Then
    #expect(style.borders == CellBorders(top: .thin, bottom: .thin))
  }

  @Test("罫線の種類と色は JSON を経ても変わらない")
  func bordersSurviveJSON() throws {
    // Given: 左だけに青い一点鎖線
    var lines = CellBorders()
    lines[.left] = BorderLine(style: .dashDot, color: color("0070C0"))

    // When
    let decoded = try JSONDecoder().decode(CellBorders.self, from: JSONEncoder().encode(lines))

    // Then
    #expect(decoded == lines)
  }
}
