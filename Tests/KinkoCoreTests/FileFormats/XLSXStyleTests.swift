import Foundation
import Testing

@testable import KinkoCore

/// 書式を試すための .xlsx（Excel の出力をまねた XML を Python の zipfile で包んだもの）。
/// Excel 2024 以降の既定テーマ（theme1.xml）、tint 付きのテーマの色、indexed の色、値のない塗りつぶしのセル、罫線、配置、
/// 組み込みとユーザー定義の表示形式（[$¥-411]#,##0 や #,##0.0_ ;[Red]\-#,##0.0\ ）、差分書式（dxfs: 無視される）、
/// 折り返しと縦の配置、行の高さ（手で決めたもの・自動のもの・セルのない行）、セルの中の改行を含む
private let styledSample = """
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
AAAABwAHAMEBAADBDQAAAAA=
"""

@Suite("XLSX の書式の読み書き")
struct XLSXStyleTests {
  private func readSample() throws -> Sheet {
    let data = try #require(Data(base64Encoded: styledSample, options: .ignoreUnknownCharacters))
    return try #require(try XLSX.read(data).sheets.first)
  }

  private func written(_ sheet: Sheet) throws -> Data {
    try XLSX.write(Workbook(sheets: [sheet])) { _, _ in .empty }
  }

  // MARK: - 読み込み

  @Test("書式付きのブックの値を読む（Alt+Enter の改行もそのまま）")
  func readsStyledValues() throws {
    // Given / When
    let sheet = try readSample()

    // Then
    #expect(
      byA1(sheet.cells) == [
        "A1": "太字", "B1": "斜体", "C1": "テーマ",
        "A2": "120", "B2": "1234", "C2": "1234.5", "D2": "1234.5",
        "A3": "0.125", "B3": "99.5", "C3": "1234567", "D3": "0.5",
        "A4": "2026/10/30", "B4": "下線", "C4": "x", "D4": "y",
        "A5": "1500", "B5": "3.5", "C5": "文字", "D5": "=A5*2", "E5": #"="a"&"b""#,
        "B6": "FALSE",
        // Excel の Alt+Enter の改行は、XML の中にそのまま LF として入っている
        "A7": "1行目\n2行目", "B7": "中", "C7": "下", "D7": "均等", "A8": "自動",
      ])
  }

  @Test("セルの文字・塗りつぶし・罫線・配置・表示形式を読む")
  func readsCellStyles() throws {
    // Given / When
    let sheet = try readSample()

    // Then: 期待する色は Python の colorsys（HLS）で別に計算したもの
    #expect(
      byA1(sheet.styles) == [
        // テーマの dk1（黒）の文字色は既定の色として持つ
        "A1": style { $0.bold = true },
        "B1": style {
          $0.italic = true
          $0.underline = true
          $0.strikethrough = true
          $0.textColor = color("FF0000")
        },
        // accent1 156082 を 80% 明るく、背景は accent2 E97132 を 60% 明るく
        "C1": style {
          $0.textColor = color("C1E5F5")
          $0.fillColor = color("F6C6AD")
        },
        // 値のないセルでも塗りつぶしと罫線は残る
        "D1": style {
          $0.fillColor = color("FFFF00")
          $0.borders = CellBorders(edges: .all)
        },
        "A2": style { $0.alignment = .center },
        "B2": style {
          $0.alignment = .right
          $0.numberFormat = .currency(decimals: 0)
        },
        "C2": style { $0.numberFormat = .number(decimals: 1, grouping: true) },
        "D2": style {
          $0.alignment = .center
          $0.numberFormat = .currency(decimals: 2)
        },
        "A3": style { $0.numberFormat = .percent(decimals: 3) },
        // ドルは ¥ にせず、カンマ区切りの数にする
        "B3": style { $0.numberFormat = .number(decimals: 2, grouping: true) },
        "C3": style { $0.numberFormat = .number(decimals: 0, grouping: true) },
        "D3": style { $0.numberFormat = .percent(decimals: 0) },
        // 日付は文字列になるので表示形式は持たない。太字は残る
        "A4": style { $0.bold = true },
        // 二重下線も下線。indexed="10" は赤。中太線（medium）の色はそのまま
        "B4": style {
          $0.underline = true
          $0.textColor = color("FF0000")
          $0.borders = CellBorders(bottom: BorderLine(style: .medium, color: color("0070C0")))
        },
        // dk2 0E2841 を 25% 暗く。lightGray の模様は前景色で塗りつぶす。均等割り付けは標準。自動の色（auto）の線は色なし
        "D4": style {
          $0.textColor = color("0B1E31")
          $0.fillColor = color("C0C0C0")
          $0.borders = CellBorders(edges: [.left, .right], line: BorderLine(style: .dashed))
        },
        // "0.0," の末尾のカンマは千で割る指定で、区切りではない
        "A5": style { $0.numberFormat = .number(decimals: 1, grouping: false) },
        "B5": style { $0.numberFormat = .currency(decimals: 2) },
        // 文字列には表示形式を付けない（配置だけ残る）
        "C5": style { $0.alignment = .right },
        // 数式でも結果が数なら表示形式を付ける
        "D5": style { $0.numberFormat = .number(decimals: 0, grouping: true) },
        // 値のない空のセルは、これから数を入れるかもしれないので表示形式を残す
        "A6": style { $0.numberFormat = .number(decimals: 1, grouping: true) },
        "B6": style { $0.alignment = .left },
        "A7": style {
          $0.wraps = true
          $0.verticalAlignment = .top
        },
        "B7": style {
          $0.alignment = .center
          $0.verticalAlignment = .center
        },
        // 下揃えは既定なので書式を持たない（C7）。縦の均等割り付けは中央
        "D7": style {
          $0.wraps = true
          $0.verticalAlignment = .center
        },
        // 罫線の種類と色: テーマの色（accent1 を 25% 暗く）、indexed の赤、黒（＝自動）、テーマの dk1（黒＝自動）
        "A11": style {
          $0.borders = CellBorders(
            top: BorderLine(style: .thick), left: BorderLine(style: .double, color: color("104862")),
            bottom: BorderLine(style: .dashDot), right: BorderLine(style: .dotted, color: color("FF0000")))
        },
        // 色のない線、indexed="64"（システムの文字色＝自動）、テーマの accent2
        "B11": style {
          $0.borders = CellBorders(
            top: BorderLine(style: .slantDashDot), left: BorderLine(style: .hair),
            bottom: BorderLine(style: .mediumDashed, color: color("E97132")),
            right: BorderLine(style: .mediumDashDotDot, color: color("00B050")))
        },
      ])
  }

  @Test("手で決めた行の高さだけを読み、2〜409 に収める")
  func readsRowHeights() throws {
    // Given / When
    let sheet = try readSample()

    // Then: 8 行目の自動の高さは捨てる
    #expect(sheet.rowHeights == [6: 45, 8: 2, 9: 409])
  }

  @Test("独自のパレットの色を使い、番号の外の書式は既定として扱う")
  func customPaletteAndUnknownStyles() throws {
    // Given: 独自のパレット（<colors>）は styles.xml の末尾にある。B1 の s="5" と C1 の s="-1" は番号の外
    let palette = (0..<64).map { #"<rgbColor rgb="\#($0 == 10 ? "FF123456" : "FFFFFFFF")"/>"# }.joined()
    let styles =
      #"<fonts count="2"><font/><font><color indexed="10"/></font></fonts>"#
      // 知らない線の種類は細線にする。色は独自のパレットから
      + #"<borders count="2"><border/><border><top style="superThick"><color indexed="10"/></top></border></borders>"#
      + #"<cellXfs count="2"><xf fontId="0"/><xf fontId="1" borderId="1"/></cellXfs>"#
      + "<colors><indexedColors>\(palette)</indexedColors></colors>"
    let data = try package(
      sheetXML: #"<row r="1"><c r="A1" s="1"><v>1</v></c><c r="B1" s="5"><v>2</v></c><c r="C1" s="-1"/></row>"#, stylesXML: styles)

    // When
    let sheet = try #require(try XLSX.read(data).sheets.first)

    // Then
    #expect(
      byA1(sheet.styles) == [
        "A1": style {
          $0.textColor = color("123456")
          $0.borders = CellBorders(top: BorderLine(style: .thin, color: color("123456")))
        }
      ])
    #expect(sheet.cells.count == 2)
  }

  @Test("書式が多すぎるブックは断る")
  func rejectsTooManyStyles() throws {
    // Given
    let data = try package(sheetXML: "", stylesXML: "<cellXfs>" + String(repeating: "<xf/>", count: XLSX.maxStyles + 2) + "</cellXfs>")

    // When / Then
    #expect(throws: SpreadsheetFileError.tooManyStyles(limit: XLSX.maxStyles)) { try XLSX.read(data) }
  }

  @Test("テーマの色の tint は Excel の色の選択肢に出る値と一致する", arguments: [
    // Office 2013〜2021 のテーマ。明るく
    ("4472C4", 0.79998168889431442, "DAE3F3"),
    ("ED7D31", 0.59999389629810485, "F8CBAD"),
    ("000000", 0.499984740745262, "7F7F7F"),
    // 暗く
    ("FFFFFF", -0.1499984740745262, "D9D9D9"),
    // 0 ならそのまま
    ("4472C4", 0, "4472C4"),
  ])
  func themeTint(base: String, tint: Double, expected: String) {
    // Given / When
    let tinted = XLSX.tinted(color(base), by: tint)

    // Then
    #expect(tinted == color(expected))
  }

  @Test("表示形式のコードを Kinko の表示形式にする", arguments: [
    // 対応しないものは標準
    ("General", NumberFormat.general), ("@", .general), ("0.00E+00", .general), ("# ?/?", .general), ("", .general),
    // 数
    ("0", .number(decimals: 0, grouping: false)),
    ("#,##0.000", .number(decimals: 3, grouping: true)),
    ("#,#", .number(decimals: 0, grouping: true)),
    ("0.0,", .number(decimals: 1, grouping: false)),
    ("#,##0.0_ ;[Red]\\-#,##0.0\\ ", .number(decimals: 1, grouping: true)),
    // 円は通貨。ドルはカンマ区切りの数
    ("[$¥-411]#,##0", .currency(decimals: 0)),
    ("[$￥-411]#,##0.00;[Red]-[$￥-411]#,##0.00", .currency(decimals: 2)),
    ("\"¥\"#,##0", .currency(decimals: 0)),
    ("\\¥#,##0.0", .currency(decimals: 1)),
    ("¥#,##0;¥\\-#,##0", .currency(decimals: 0)),
    ("[$$-409]#,##0.00", .number(decimals: 2, grouping: true)),
    // パーセント（小数は 10 桁まで）
    ("0.0%", .percent(decimals: 1)),
    ("[Red]0%", .percent(decimals: 0)),
    ("0.000000000000%", .percent(decimals: 10)),
    // 引用符の中の文字は飾り
    ("\"合計\"#,##0\"円\"", .number(decimals: 0, grouping: true)),
  ] as [(String, NumberFormat)])
  func numberFormat(code: String, expected: NumberFormat) {
    // Given / When
    let format = XLSX.numberFormat(formatCode: code)

    // Then
    #expect(format == expected)
  }

  // MARK: - 書き出し: 文字・塗りつぶし・表示形式

  /// 同じ書式の A1・A2、別の書式の B1、値のない書式だけの C1〜C3、表示形式 12 種類の F1〜F12
  private var formattedSheet: Sheet {
    let shared = style {
      $0.bold = true
      $0.italic = true
      $0.underline = true
      $0.strikethrough = true
      $0.textColor = color("112233")
      $0.fillColor = color("AABBCC")
      $0.borders = CellBorders(edges: .all, line: BorderLine(style: .double, color: color("00B050")))
      $0.alignment = .center
      $0.numberFormat = .currency(decimals: 2)
    }
    var sheet = Sheet(name: "書式", cells: ["A1": "1", "A2": "2", "B1": "文字"])
    sheet[style: "A1"] = shared
    sheet[style: "A2"] = shared
    sheet[style: "B1"] = style {
      $0.textColor = color("FF0000")
      $0.alignment = .right
      $0.borders = CellBorders(edges: [.top, .bottom])
    }
    sheet[style: "C1"] = style { $0.fillColor = color("FFFF00") }
    sheet[style: "C2"] = style { $0.borders = CellBorders(left: BorderLine(style: .thick)) }
    sheet[style: "C3"] = style { $0.alignment = .left }
    let formats: [NumberFormat] = [
      .number(decimals: 0, grouping: false), .number(decimals: 2, grouping: false), .number(decimals: 0, grouping: true),
      .number(decimals: 2, grouping: true), .number(decimals: 3, grouping: false), .number(decimals: 1, grouping: true),
      .currency(decimals: 0), .currency(decimals: 2), .currency(decimals: 4), .percent(decimals: 0), .percent(decimals: 2),
      .percent(decimals: 1),
    ]
    for (row, format) in formats.enumerated() {
      let address = CellAddress(row: row, column: 5)
      sheet[address] = "1234.5"
      sheet[style: address] = style { $0.numberFormat = format }
    }
    return sheet
  }

  @Test("書式を書いて読み戻せる")
  func writeThenReadStyles() throws {
    // Given
    let sheet = formattedSheet

    // When
    let read = try #require(try XLSX.read(written(sheet)).sheets.first)

    // Then
    #expect(read.styles == sheet.styles)
    #expect(read.cells == sheet.cells)
  }

  @Test("同じ書式のセルは同じ番号を使い、書式だけのセルは値なしで書く")
  func writesStyleIndexes() throws {
    // Given / When
    let xml = try xmlPart("xl/worksheets/sheet1.xml", in: written(formattedSheet))

    // Then
    #expect(xml.contains(#"<c r="A1" s="1"><v>1</v></c>"#))
    #expect(xml.contains(#"<c r="A2" s="1"><v>2</v></c>"#))
    #expect(xml.contains(#"<c r="C1" s="3"/>"#))
  }

  @Test("styles.xml には使う書式と、組み込みにない表示形式だけを書く")
  func writesStylesPart() throws {
    // Given / When
    let styles = try xmlPart("xl/styles.xml", in: written(formattedSheet))

    // Then: 既定 1 + 共有 1 + B1 + C1〜C3 + 表示形式 12 = 18
    #expect(styles.contains(#"<cellXfs count="18">"#))
    // 組み込みの番号（1〜4, 9, 10）にないものだけがユーザー定義になる
    #expect(styles.contains(#"<numFmts count="6">"#))
    #expect(styles.contains(#"formatCode="[$¥-411]#,##0.00""#))
    // Excel が決まって置く 2 つの塗りつぶし
    #expect(styles.contains(#"<fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>"#))
  }

  // MARK: - 書き出し: 配置と行の高さ

  /// 折り返して上揃えの A1・A2（改行あり）、値のない B1、折り返しだけの B2。1・2・5・100 行目に高さ
  private var alignedSheet: Sheet {
    let wrapTop = style {
      $0.wraps = true
      $0.verticalAlignment = .top
    }
    var sheet = Sheet(name: "配置", cells: ["A1": "1行目\n2行目\n\n4行目", "A2": "改行だけ\n", "B2": "x"])
    sheet[style: "A1"] = wrapTop
    sheet[style: "A2"] = wrapTop
    sheet[style: "B1"] = style {
      $0.alignment = .right
      $0.verticalAlignment = .center
    }
    sheet[style: "B2"] = style { $0.wraps = true }
    // 1 行目と 2 行目はセルあり、5 行目と 100 行目はセルなし
    sheet.rowHeights = [0: 45, 1: 18.75, 4: 30, 99: 2]
    return sheet
  }

  @Test("配置と行の高さを書いて読み戻せる")
  func writeThenReadAlignment() throws {
    // Given
    let sheet = alignedSheet

    // When
    let read = try #require(try XLSX.read(written(sheet)).sheets.first)

    // Then
    #expect(read.cells == sheet.cells)
    #expect(read.styles == sheet.styles)
    #expect(read.rowHeights == sheet.rowHeights)
  }

  @Test("セルのない行も行の順に空の <row> として書き、改行は文字参照で残す")
  func writesRows() throws {
    // Given / When
    let xml = try xmlPart("xl/worksheets/sheet1.xml", in: written(alignedSheet))

    // Then
    #expect(xml.contains(#"<row r="2" ht="18.75" customHeight="1"><c r="A2" s="1" t="inlineStr"><is><t xml:space="preserve">改行だけ&#10;</t></is></c>"#))
    #expect(xml.contains(#"</row><row r="5" ht="30.0" customHeight="1"/><row r="100" ht="2.0" customHeight="1"/></sheetData>"#))
  }

  @Test("配置を styles.xml に書き、同じ書式は 1 つにまとめる")
  func writesAlignment() throws {
    // Given / When
    let styles = try xmlPart("xl/styles.xml", in: written(alignedSheet))

    // Then
    #expect(styles.contains(#"applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>"#))
    #expect(styles.contains(#"<alignment horizontal="right" vertical="center"/>"#))
    // 同じ書式の A1 と A2 は 1 つにまとまる（既定 + 3 種類）
    #expect(styles.contains(#"<cellXfs count="4">"#))
  }

  // MARK: - 書き出し: 罫線

  /// 13 種類すべての線を、色あり（上下）・色なし（左右）で 4 辺に引いた A1〜A13 と、右の 1 辺だけの C1
  private var borderedSheet: Sheet {
    var sheet = Sheet(name: "罫線")
    for (row, kind) in BorderStyle.allCases.enumerated() {
      let colored = BorderLine(style: kind, color: color(String(format: "%02X%02X%02X", row * 19, 255 - row * 19, 128)))
      sheet[style: CellAddress(row: row, column: 0)] = style {
        $0.borders = CellBorders(top: colored, left: BorderLine(style: kind), bottom: colored, right: BorderLine(style: kind))
      }
    }
    sheet[style: "C1"] = style { $0.borders = CellBorders(right: BorderLine(style: .double, color: color("FF0000"))) }
    return sheet
  }

  @Test("すべての種類の罫線を書いて読み戻せる")
  func writeThenReadBorders() throws {
    // Given
    let sheet = borderedSheet

    // When
    let read = try #require(try XLSX.read(written(sheet)).sheets.first)

    // Then
    #expect(read.styles == sheet.styles)
  }

  @Test("罫線を styles.xml に書く（線のない辺は空の要素、色のない線は自動の色）")
  func writesBorders() throws {
    // Given / When
    let styles = try xmlPart("xl/styles.xml", in: written(borderedSheet))

    // Then
    #expect(styles.contains(#"<border><left/><right style="double"><color rgb="FFFF0000"/></right><top/><bottom/><diagonal/></border>"#))
    #expect(styles.contains(#"<left style="mediumDashDotDot"><color indexed="64"/></left>"#))
    // 既定（空）+ 13 種類 + 1 辺だけ
    #expect(styles.contains(#"<borders count="15">"#))
  }

  // MARK: - フォント

  @Test("フォントの種類と大きさを書いて読み戻せ、既定のフォントの 11 ポイントは持たない")
  func writeThenReadFonts() throws {
    // Given: 明朝の 18 ポイント、10.5 ポイント、既定のフォント
    var sheet = Sheet(name: "S", cells: ["A1": "見出し", "A2": "注", "A3": "本文"])
    sheet[style: "A1"] = style {
      $0.fontName = "Hiragino Mincho ProN"
      $0.fontSize = 18
    }
    sheet[style: "A2"] = style { $0.fontSize = 10.5 }

    // When
    let data = try written(sheet)
    let read = try #require(try XLSX.read(data).sheets.first)
    let styles = try xmlPart("xl/styles.xml", in: data)

    // Then: 大きさは整数なら小数点なしで書く
    #expect(read.styles == sheet.styles)
    #expect(styles.contains(#"<sz val="18"/><name val="Hiragino Mincho ProN"/>"#))
    #expect(styles.contains(#"<sz val="10.5"/><name val="Calibri"/>"#))
  }

  @Test("ブックの既定のフォント（0 番）と同じ種類は持たず、大きさは範囲に収める")
  func readsFontsRelativeToDefault() throws {
    // Given: 既定は游ゴシック 11。1 番は同じ游ゴシックの 14、2 番は Arial の 500 ポイント
    let fonts = #"<fonts count="3"><font><sz val="11"/><name val="游ゴシック"/></font><font><sz val="14"/><name val="游ゴシック"/></font><font><sz val="500"/><name val="Arial"/></font></fonts>"#
    let xfs = #"<cellXfs count="3"><xf fontId="0"/><xf fontId="1"/><xf fontId="2"/></cellXfs>"#
    let data = try package(
      sheetXML: #"<row r="1"><c r="A1" s="1"><v>1</v></c><c r="B1" s="2"><v>2</v></c></row>"#, stylesXML: fonts + xfs)

    // When
    let sheet = try #require(try XLSX.read(data).sheets.first)

    // Then
    #expect(sheet[style: "A1"] == style { $0.fontSize = 14 })
    #expect(sheet[style: "B1"] == style {
      $0.fontName = "Arial"
      $0.fontSize = 409
    })
  }
}
