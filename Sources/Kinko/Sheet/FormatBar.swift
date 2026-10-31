import KinkoCore
import SwiftUI

/// 書式バー。入力先のセルの書式を表示し、押すと選んだ範囲に反映する。
/// ボタンは機能ごとのまとまりで並べ、ウィンドウが狭いときはまとまりごと次の行へ折り返す（隠れるボタンを作らない）
struct FormatBar: View {
  @Bindable var model: SheetEditorModel
  @State private var isEditingBorders = false

  static let textPalette = [
    "C00000", "FF0000", "FFC000", "00B050", "0070C0", "7030A0",
    "833C0B", "806000", "375623", "1F4E78", "808080", "FFFFFF",
  ]
  private static let fillPalette = [
    "FCE4D6", "FFF2CC", "E2EFDA", "DDEBF7", "E4DFEC", "F2F2F2",
    "FF7C80", "FFFF00", "92D050", "00B0F0", "B4A7D6", "BFBFBF",
  ]

  var body: some View {
    let style = model.activeStyle
    // Google スプレッドシートと同じく、まとまりの間に縦線を入れる。折り返した行の端には縦線を出さない
    FlowLayout(spacing: 6, lineSpacing: 4) {
      HStack(spacing: 2) {
        FormatToggle(title: "元に戻す（⌘Z）", symbol: "arrow.uturn.backward", isOn: false) { model.undo() }
          .disabled(!model.canUndo)
        FormatToggle(title: "やり直す（⇧⌘Z）", symbol: "arrow.uturn.forward", isOn: false) { model.redo() }
          .disabled(!model.canRedo)
      }
      ToolbarSeparator()
      HStack(spacing: 2) {
        FontFamilyMenu(current: style.fontName) { model.setFontName($0) }
        Menu {
          Picker("文字の大きさ", selection: Binding(get: { style.fontSize ?? CellStyle.defaultFontSize }, set: { model.setFontSize($0) })) {
            ForEach(SheetEditorModel.fontSizes, id: \.self) { size in
              Text(Self.sizeText(size)).tag(size)
            }
          }
          .pickerStyle(.inline)
          .labelsHidden()
        } label: {
          Text(Self.sizeText(style.fontSize ?? CellStyle.defaultFontSize)).monospacedDigit()
        }
        .menuStyle(.borderlessButton)
        .frame(width: 48)
        .hoverLabel("文字の大きさ（ポイント）")
        FormatToggle(title: "文字を大きく", symbol: "textformat.size.larger", isOn: false) { model.stepFontSize(up: true) }
        FormatToggle(title: "文字を小さく", symbol: "textformat.size.smaller", isOn: false) { model.stepFontSize(up: false) }
      }
      ToolbarSeparator()
      HStack(spacing: 2) {
        FormatToggle(title: "太字（⌘B）", symbol: "bold", isOn: style.bold) { model.toggle(\.bold) }
          .keyboardShortcut("b")
        FormatToggle(title: "斜体（⌘I）", symbol: "italic", isOn: style.italic) { model.toggle(\.italic) }
          .keyboardShortcut("i")
        FormatToggle(title: "下線（⌘U）", symbol: "underline", isOn: style.underline) { model.toggle(\.underline) }
          .keyboardShortcut("u")
        FormatToggle(title: "取り消し線", symbol: "strikethrough", isOn: style.strikethrough) { model.toggle(\.strikethrough) }
        ColorButton(title: "文字の色", current: style.textColor, palette: Self.textPalette, noneLabel: "自動") { color in
          model.applyStyle { $0.textColor = color }
        } label: {
          Text("A").font(.system(size: 13, weight: .semibold))
        }
      }
      ToolbarSeparator()
      HStack(spacing: 2) {
        ColorButton(title: "塗りつぶしの色", current: style.fillColor, palette: Self.fillPalette, noneLabel: "塗りつぶしなし") { color in
          model.applyStyle { $0.fillColor = color }
        } label: {
          Image(systemName: "paintbrush.fill").font(.system(size: 11))
        }
        Button {
          isEditingBorders = true
        } label: {
          Image(systemName: "squareshape.split.2x2").frame(width: 26, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .hoverLabel("枠線（場所・線の種類・色）")
        .accessibilityLabel("枠線")
        .popover(isPresented: $isEditingBorders) { BorderPanel(model: model) }
      }
      ToolbarSeparator()
      HStack(spacing: 2) {
        OptionMenu(
          title: "水平方向の配置", options: [KinkoCore.HorizontalAlignment.left, .center, .right], selected: style.alignment,
          name: { ["left": "左揃え", "center": "中央揃え", "right": "右揃え"][$0.rawValue]! }
        ) { alignment in
          Image(systemName: "text.align\(alignment?.rawValue ?? "left")")
        } apply: { model.setAlignment($0) }
        OptionMenu(
          title: "垂直方向の配置", options: [KinkoCore.VerticalAlignment.top, .center, .bottom], selected: style.verticalAlignment ?? .bottom,
          name: { ["top": "上揃え", "center": "上下中央揃え", "bottom": "下揃え"][$0.rawValue]! }
        ) { alignment in
          Image(systemName: Self.verticalSymbol(alignment ?? .bottom))
        } apply: { model.setVerticalAlignment($0) }
        OptionMenu(
          title: "テキストの折り返し", options: SheetEditorModel.TextOverflow.allCases, selected: model.activeOverflow, name: \.title
        ) { overflow in
          OverflowIcon(overflow: overflow ?? .overflow)
        } apply: { model.setOverflow($0) }
      }
      ToolbarSeparator()
      HStack(spacing: 2) {
        Menu {
          Button("標準") { model.setNumberFormat(.general) }
          Button("数値（1234.00）") { model.setNumberFormat(.number(decimals: 2, grouping: false)) }
          Button("桁区切り（1,234）") { model.setNumberFormat(.number(decimals: 0, grouping: true)) }
          Button("通貨（¥1,234）") { model.setNumberFormat(.currency(decimals: 0)) }
          Button("パーセント（12%）") { model.setNumberFormat(.percent(decimals: 0)) }
        } label: {
          Text(Self.formatName(style.numberFormat))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .hoverLabel("表示形式")
        FormatToggle(title: "小数点以下の桁を増やす", text: "+.0", isOn: false) { model.changeDecimals(by: 1) }
        FormatToggle(title: "小数点以下の桁を減らす", text: "−.0", isOn: false) { model.changeDecimals(by: -1) }
      }
      ToolbarSeparator()
      HStack(spacing: 2) {
        Menu {
          Button("昇順（小さい順）") { model.sort(ascending: true) }
          Button("降順（大きい順）") { model.sort(ascending: false) }
        } label: {
          Image(systemName: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .hoverLabel("選んだ行を、入力先のセルの列で並べ替える")
        FormatToggle(title: "書式をクリア", symbol: "eraser", isOn: false) { model.clearFormats() }
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
  }

  static func verticalSymbol(_ alignment: KinkoCore.VerticalAlignment) -> String {
    switch alignment {
    case .top: "arrow.up.to.line"
    case .center: "arrow.down.and.line.horizontal.and.arrow.up"
    case .bottom: "arrow.down.to.line"
    }
  }

  /// 11 や 10.5
  static func sizeText(_ size: Double) -> String {
    size == size.rounded() ? String(Int(size)) : String(size)
  }

  static func formatName(_ format: NumberFormat) -> String {
    switch format {
    case .general: "標準"
    case .number(_, let grouping): grouping ? "桁区切り" : "数値"
    case .currency: "通貨"
    case .percent: "パーセント"
    }
  }
}

/// フォントの種類を選ぶメニュー。よく使うものを並べ、それ以外は「ほかのフォント…」の一覧から選ぶ
private struct FontFamilyMenu: View {
  let current: String?
  let apply: (String?) -> Void
  @State private var isChoosingOther = false

  /// よく使うフォント。この Mac にあるものだけを出す
  private static let common: [String] = {
    let installed = Set(NSFontManager.shared.availableFontFamilies)
    return [
      "Hiragino Sans", "Hiragino Mincho ProN", "Hiragino Maru Gothic ProN", "YuGothic", "YuMincho", "Osaka", "Klee",
      "Helvetica Neue", "Arial", "Times New Roman", "Georgia", "Courier New", "Menlo",
    ].filter(installed.contains)
  }()

  /// 「ヒラギノ角ゴシック」のような、この Mac の言語での名前
  static func displayName(_ family: String) -> String {
    NSFontManager.shared.localizedName(forFamily: family, face: nil)
  }

  var body: some View {
    Menu {
      Picker("フォント", selection: Binding(get: { current ?? "" }, set: { apply($0.isEmpty ? nil : $0) })) {
        Text("標準のフォント").tag("")
        Divider()
        ForEach(Self.common, id: \.self) { family in
          Text(Self.displayName(family)).tag(family)
        }
        // 一覧にないフォント（読み込んだ .xlsx のものなど）も、選んでいることが分かるように出す
        if let current, !Self.common.contains(current) {
          Divider()
          Text(Self.displayName(current)).tag(current)
        }
      }
      .pickerStyle(.inline)
      .labelsHidden()
      Divider()
      Button("ほかのフォント…") { isChoosingOther = true }
    } label: {
      Text(current.map(Self.displayName) ?? "標準のフォント").lineLimit(1)
    }
    .menuStyle(.borderlessButton)
    .frame(width: 132)
    .hoverLabel("フォント")
    .popover(isPresented: $isChoosingOther) {
      AllFontsList(current: current) { family in
        apply(family)
        isChoosingOther = false
      }
    }
  }
}

/// この Mac にあるすべてのフォントから選ぶ。名前で絞り込める
private struct AllFontsList: View {
  let current: String?
  let apply: (String) -> Void
  @State private var query = ""

  private var families: [String] {
    let all = NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }
    guard !query.isEmpty else { return all }
    return all.filter { $0.localizedCaseInsensitiveContains(query) || FontFamilyMenu.displayName($0).localizedCaseInsensitiveContains(query) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      TextField("フォントを探す", text: $query).textFieldStyle(.roundedBorder)
      List(families, id: \.self) { family in
        Button {
          apply(family)
        } label: {
          HStack {
            // 名前はそのフォントで見せる
            Text(FontFamilyMenu.displayName(family)).font(.custom(family, size: 13))
            Spacer()
            if family == current { Image(systemName: "checkmark") }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
      .listStyle(.plain)
    }
    .padding(12)
    .frame(width: 260, height: 340)
  }
}

/// 書式バーのまとまりの間の縦線。大きさは FlowLayout が決める（行の端に来たときは大きさ 0 にして隠す）
private struct ToolbarSeparator: View {
  var body: some View {
    Rectangle()
      .fill(Color(nsColor: .separatorColor))
      .layoutValue(key: IsSeparator.self, value: true)
  }
}

private struct IsSeparator: LayoutValueKey {
  static let defaultValue = false
}

/// 子を左から並べ、幅が足りなくなったら次の行へ送る。縦線（ToolbarSeparator）は、前後のまとまりが同じ行に並ぶときだけ出す
private struct FlowLayout: Layout {
  var spacing: CGFloat
  var lineSpacing: CGFloat

  private struct Item {
    var index: Int
    var size: CGSize
    var isSeparator = false
  }

  private func rows(for width: CGFloat, subviews: Subviews) -> [[Item]] {
    var rows: [[Item]] = [[]]
    var x: CGFloat = 0
    var separator: Int?
    for (index, subview) in subviews.enumerated() {
      if subview[IsSeparator.self] {
        separator = index
        continue
      }
      let size = subview.sizeThatFits(.unspecified)
      let separatorWidth: CGFloat = separator == nil ? 0 : 1 + spacing
      if x > 0, x + separatorWidth + size.width > width {
        rows.append([])
        x = 0
      } else if let separator, x > 0 {
        rows[rows.count - 1].append(Item(index: separator, size: CGSize(width: 1, height: 0), isSeparator: true))
        x += separatorWidth
      }
      separator = nil
      rows[rows.count - 1].append(Item(index: index, size: size))
      x += size.width + spacing
    }
    return rows
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? .infinity
    let rows = rows(for: width, subviews: subviews)
    let height = rows.map { $0.map(\.size.height).max() ?? 0 }.reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
    let widest = rows.map { row in row.map(\.size.width).reduce(0, +) + spacing * CGFloat(max(0, row.count - 1)) }.max() ?? 0
    return CGSize(width: width.isFinite ? width : widest, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var placed = Set<Int>()
    var y = bounds.minY
    for row in rows(for: bounds.width, subviews: subviews) {
      let height = row.map(\.size.height).max() ?? 0
      var x = bounds.minX
      for item in row {
        // 縦線は行の高さより少し短くする
        let size = item.isSeparator ? CGSize(width: 1, height: max(0, height - 8)) : item.size
        subviews[item.index].place(at: CGPoint(x: x, y: y + (height - size.height) / 2), proposal: ProposedViewSize(size))
        placed.insert(item.index)
        x += size.width + spacing
      }
      y += height + lineSpacing
    }
    // 行の端に来て出さない縦線は、大きさ 0 で置く
    for index in subviews.indices where !placed.contains(index) {
      subviews[index].place(at: bounds.origin, proposal: .zero)
    }
  }
}

/// 書式バーのボタン。オンのときは背景に色を付ける
private struct FormatToggle: View {
  let title: String
  var symbol: String?
  var text: String?
  let isOn: Bool
  let action: () -> Void

  init(title: String, symbol: String, isOn: Bool, action: @escaping () -> Void) {
    self.title = title
    self.symbol = symbol
    self.isOn = isOn
    self.action = action
  }

  init(title: String, text: String, isOn: Bool, action: @escaping () -> Void) {
    self.title = title
    self.text = text
    self.isOn = isOn
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      Group {
        if let symbol {
          Image(systemName: symbol)
        } else {
          Text(text ?? "").font(.system(size: 11, weight: .medium).monospacedDigit())
        }
      }
      .frame(width: 26, height: 22)
      .background(isOn ? Color.accentColor.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 5))
      .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .hoverLabel(title)
    .accessibilityLabel(title)
  }
}

/// 今の選択肢のアイコンと ▾ を出し、押すと選択肢のアイコンを横に並べた小窓を出す（Google スプレッドシートと同じ形）。
/// selected が nil（標準）のときは、icon に nil を渡したアイコンを出し、どれも選んでいない形にする
private struct OptionMenu<Option: Hashable, Icon: View>: View {
  let title: String
  let options: [Option]
  let selected: Option?
  let name: (Option) -> String
  @ViewBuilder let icon: (Option?) -> Icon
  let apply: (Option) -> Void

  @State private var isShowing = false

  var body: some View {
    Button {
      isShowing = true
    } label: {
      HStack(spacing: 2) {
        icon(selected)
        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
      }
      .frame(height: 22)
      .padding(.horizontal, 4)
      .background(isShowing ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 5))
      .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .hoverLabel(title)
    .accessibilityLabel(title)
    .popover(isPresented: $isShowing, arrowEdge: .bottom) {
      OptionPalette(options: options, selected: selected, name: name, icon: { icon($0) }) { option in
        apply(option)
        isShowing = false
      }
    }
  }
}

/// OptionMenu の小窓の中身。選んでいるものに色を付ける
struct OptionPalette<Option: Hashable, Icon: View>: View {
  let options: [Option]
  let selected: Option?
  let name: (Option) -> String
  @ViewBuilder let icon: (Option) -> Icon
  let apply: (Option) -> Void

  var body: some View {
    HStack(spacing: 4) {
      ForEach(options, id: \.self) { option in
        Button {
          apply(option)
        } label: {
          icon(option)
            .frame(width: 32, height: 28)
            .background(option == selected ? Color.accentColor.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .hoverLabel(name(option))
        .accessibilityLabel(name(option))
      }
    }
    .padding(6)
  }
}

/// 折り返しの 3 つのアイコン。SF Symbols にちょうどよいものがないので線で描く
struct OverflowIcon: View {
  let overflow: SheetEditorModel.TextOverflow

  var body: some View {
    Canvas { context, size in
      let w = size.width, h = size.height
      var lines = Path()
      var arrow = Path()
      switch overflow {
      case .overflow:
        // セルの右端の線を、矢印が突き抜ける
        lines.move(to: CGPoint(x: w * 0.2, y: h * 0.15))
        lines.addLine(to: CGPoint(x: w * 0.2, y: h * 0.85))
        lines.move(to: CGPoint(x: w * 0.55, y: h * 0.15))
        lines.addLine(to: CGPoint(x: w * 0.55, y: h * 0.85))
        arrow.move(to: CGPoint(x: w * 0.3, y: h * 0.5))
        arrow.addLine(to: CGPoint(x: w * 0.9, y: h * 0.5))
        arrow.move(to: CGPoint(x: w * 0.75, y: h * 0.35))
        arrow.addLine(to: CGPoint(x: w * 0.9, y: h * 0.5))
        arrow.addLine(to: CGPoint(x: w * 0.75, y: h * 0.65))
      case .wrap:
        // 右端の線の手前で折り返して、次の行へ戻る
        lines.move(to: CGPoint(x: w * 0.15, y: h * 0.15))
        lines.addLine(to: CGPoint(x: w * 0.15, y: h * 0.85))
        lines.move(to: CGPoint(x: w * 0.85, y: h * 0.15))
        lines.addLine(to: CGPoint(x: w * 0.85, y: h * 0.85))
        arrow.move(to: CGPoint(x: w * 0.28, y: h * 0.3))
        arrow.addLine(to: CGPoint(x: w * 0.55, y: h * 0.3))
        arrow.addArc(center: CGPoint(x: w * 0.55, y: h * 0.5), radius: h * 0.2, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        arrow.addLine(to: CGPoint(x: w * 0.32, y: h * 0.7))
        arrow.move(to: CGPoint(x: w * 0.45, y: h * 0.57))
        arrow.addLine(to: CGPoint(x: w * 0.32, y: h * 0.7))
        arrow.addLine(to: CGPoint(x: w * 0.45, y: h * 0.83))
      case .clip:
        // 両端の線の間で止まる
        lines.move(to: CGPoint(x: w * 0.15, y: h * 0.15))
        lines.addLine(to: CGPoint(x: w * 0.15, y: h * 0.85))
        lines.move(to: CGPoint(x: w * 0.85, y: h * 0.15))
        lines.addLine(to: CGPoint(x: w * 0.85, y: h * 0.85))
        arrow.move(to: CGPoint(x: w * 0.15, y: h * 0.5))
        arrow.addLine(to: CGPoint(x: w * 0.85, y: h * 0.5))
      }
      let style = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
      context.stroke(lines, with: .foreground, style: style)
      context.stroke(arrow, with: .foreground, style: style)
    }
    .frame(width: 18, height: 16)
  }
}

/// 色を選ぶボタン。押すと色見本を出す。下の線が今の色
private struct ColorButton<Label: View>: View {
  let title: String
  let current: CellColor?
  let palette: [String]
  let noneLabel: String
  let apply: (CellColor?) -> Void
  @ViewBuilder let label: () -> Label

  @State private var isShowing = false

  var body: some View {
    Button {
      isShowing = true
    } label: {
      VStack(spacing: 1) {
        label()
        RoundedRectangle(cornerRadius: 1)
          .fill(current.map { Color(nsColor: $0.nsColor) } ?? Color.secondary.opacity(0.35))
          .frame(width: 16, height: 3)
      }
      .frame(width: 28, height: 24)
      .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .hoverLabel(title)
    .accessibilityLabel(title)
    .popover(isPresented: $isShowing) {
      VStack(alignment: .leading, spacing: 10) {
        Text(title).font(.headline)
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 6), count: 6), spacing: 6) {
          ForEach(palette, id: \.self) { hex in
            let color = CellColor(hex: hex)!
            Button {
              apply(color)
              isShowing = false
            } label: {
              RoundedRectangle(cornerRadius: 5)
                .fill(Color(nsColor: color.nsColor))
                .frame(width: 24, height: 24)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(current == color ? 0.9 : 0.15), lineWidth: current == color ? 2 : 1))
            }
            .buttonStyle(.plain)
          }
        }
        Button(noneLabel) {
          apply(nil)
          isShowing = false
        }
      }
      .padding(14)
    }
  }
}
