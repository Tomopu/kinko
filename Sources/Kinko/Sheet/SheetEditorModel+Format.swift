import KinkoCore

extension SheetEditorModel {
  /// 書式を変えるセル。行・列をまるごと選んだときは、中身か書式のあるセルだけにする
  private var styleTargets: [CellAddress] {
    if selection.rowCount * selection.columnCount <= 200_000 {
      return selection.rows.flatMap { row in selection.columns.map { CellAddress(row: row, column: $0) } }
    }
    return Set(sheet.cells.keys).union(sheet.styles.keys).filter(selection.contains)
  }

  func applyStyle(_ change: (inout CellStyle) -> Void) {
    let targets = styleTargets
    commit { workbook in
      for address in targets { change(&workbook.sheets[sheetIndex][style: address]) }
    }
  }

  /// 太字などの切り替え。入力先のセルに合わせて、選んだ範囲をそろえる（Excel と同じ）
  func toggle(_ keyPath: WritableKeyPath<CellStyle, Bool>) {
    let on = !activeStyle[keyPath: keyPath]
    applyStyle { $0[keyPath: keyPath] = on }
  }

  /// 列の幅に収まらない文字の見せ方
  enum TextOverflow: CaseIterable {
    /// 右隣が空なら、はみ出して見せる（既定）
    case overflow
    /// 列の幅で折り返して、複数行で見せる
    case wrap
    /// セルの幅で切る
    case clip

    var title: String {
      switch self {
      case .overflow: "はみ出す"
      case .wrap: "折り返す（セルの中の改行は option + Return）"
      case .clip: "切り詰める"
      }
    }
  }

  var activeOverflow: TextOverflow {
    let style = activeStyle
    return style.wraps ? .wrap : style.clips ? .clip : .overflow
  }

  func setOverflow(_ overflow: TextOverflow) {
    applyStyle {
      $0.wraps = overflow == .wrap
      $0.clips = overflow == .clip
    }
  }

  func setVerticalAlignment(_ alignment: VerticalAlignment) {
    // 下揃えは既定（nil）として持つ
    let value: VerticalAlignment? = alignment == .bottom ? nil : alignment
    applyStyle { $0.verticalAlignment = value }
  }

  func setAlignment(_ alignment: HorizontalAlignment?) {
    let value = activeStyle.alignment == alignment ? nil : alignment
    applyStyle { $0.alignment = value }
  }

  /// フォントの種類。nil なら既定のフォントに戻す
  func setFontName(_ name: String?) {
    applyStyle { $0.fontName = name }
  }

  /// 文字の大きさ。既定の 11 は持たない
  func setFontSize(_ size: Double) {
    let size = min(max(size, CellStyle.fontSizes.lowerBound), CellStyle.fontSizes.upperBound)
    applyStyle { $0.fontSize = size == CellStyle.defaultFontSize ? nil : size }
  }

  /// 文字を 1 段階大きく（小さく）する。段階は書式バーの大きさの一覧と同じ
  func stepFontSize(up: Bool) {
    let current = activeStyle.fontSize ?? CellStyle.defaultFontSize
    let next = up ? Self.fontSizes.first { $0 > current } : Self.fontSizes.last { $0 < current }
    if let next { setFontSize(next) }
  }

  /// 書式バーで選べる文字の大きさ（Excel と同じ並び）
  static let fontSizes: [Double] = [8, 9, 10, 11, 12, 14, 16, 18, 20, 22, 24, 26, 28, 36, 48, 72]

  func setNumberFormat(_ format: NumberFormat) {
    applyStyle { $0.numberFormat = format }
  }

  func changeDecimals(by delta: Int) {
    let format = activeStyle.numberFormat
    // 標準のときは、今の表示の桁数から増やす
    let current = format == .general ? decimalsShown(at: active) : format.decimals
    applyStyle { $0.numberFormat = format.withDecimals(current + delta) }
  }

  private func decimalsShown(at address: CellAddress) -> Int {
    let text = displayText(at: address)
    guard let dot = text.firstIndex(of: ".") else { return 0 }
    return text[text.index(after: dot)...].prefix { $0.isNumber }.count
  }

  /// 罫線をどこに引くか
  enum BorderPlacement: CaseIterable {
    case grid, outline, inside, insideHorizontal, insideVertical, top, bottom, left, right, none

    var title: String {
      switch self {
      case .grid: "格子"
      case .outline: "外枠"
      case .inside: "内側"
      case .insideHorizontal: "内側の横線"
      case .insideVertical: "内側の縦線"
      case .top: "上"
      case .bottom: "下"
      case .left: "左"
      case .right: "右"
      case .none: "罫線なし"
      }
    }
  }

  /// 選んだ範囲に、borderLine の線で罫線を引く（none なら消す）。
  /// 範囲の外側の辺を変えるときは、隣のセルの向かい合う辺を消して、新しい線が見えるようにする
  func setBorders(_ placement: BorderPlacement) {
    let range = selection
    let targets = styleTargets
    let line = borderLine
    let sheetIndex = sheetIndex
    commit { workbook in
      func clearFacing(_ address: CellAddress, _ edge: BorderEdges) {
        guard address.isValid, !range.contains(address) else { return }
        workbook.sheets[sheetIndex][style: address].borders[edge] = nil
      }
      for address in targets {
        let isTop = address.row == range.start.row, isBottom = address.row == range.end.row
        let isLeft = address.column == range.start.column, isRight = address.column == range.end.column
        var borders = workbook.sheets[sheetIndex][style: address].borders
        var outer: BorderEdges = []
        switch placement {
        case .none:
          borders = CellBorders()
          outer = [.top, .bottom, .left, .right]
        case .grid:
          borders = CellBorders(edges: .all, line: line)
          outer = .all
        case .outline:
          if isTop { borders.top = line; outer.insert(.top) }
          if isBottom { borders.bottom = line; outer.insert(.bottom) }
          if isLeft { borders.left = line; outer.insert(.left) }
          if isRight { borders.right = line; outer.insert(.right) }
        case .inside, .insideHorizontal, .insideVertical:
          if placement != .insideVertical {
            if !isTop { borders.top = line }
            if !isBottom { borders.bottom = line }
          }
          if placement != .insideHorizontal {
            if !isLeft { borders.left = line }
            if !isRight { borders.right = line }
          }
        case .top: if isTop { borders.top = line; outer.insert(.top) }
        case .bottom: if isBottom { borders.bottom = line; outer.insert(.bottom) }
        case .left: if isLeft { borders.left = line; outer.insert(.left) }
        case .right: if isRight { borders.right = line; outer.insert(.right) }
        }
        workbook.sheets[sheetIndex][style: address].borders = borders
        if outer.contains(.top), isTop { clearFacing(CellAddress(row: address.row - 1, column: address.column), .bottom) }
        if outer.contains(.bottom), isBottom { clearFacing(CellAddress(row: address.row + 1, column: address.column), .top) }
        if outer.contains(.left), isLeft { clearFacing(CellAddress(row: address.row, column: address.column - 1), .right) }
        if outer.contains(.right), isRight { clearFacing(CellAddress(row: address.row, column: address.column + 1), .left) }
      }
    }
  }

  func clearFormats() {
    let targets = styleTargets
    commit { workbook in
      for address in targets { workbook.sheets[sheetIndex][style: address] = CellStyle() }
    }
  }
}
