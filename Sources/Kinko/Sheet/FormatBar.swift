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
    FlowLayout(spacing: 10, lineSpacing: 4) {
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
        ColorButton(title: "塗りつぶしの色", current: style.fillColor, palette: Self.fillPalette, noneLabel: "塗りつぶしなし") { color in
          model.applyStyle { $0.fillColor = color }
        } label: {
          Image(systemName: "paintbrush.fill").font(.system(size: 11))
        }
        Button {
          isEditingBorders = true
        } label: {
          Image(systemName: "square.dashed").frame(width: 26, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .hoverLabel("罫線（場所・線の種類・色）")
        .accessibilityLabel("罫線")
        .popover(isPresented: $isEditingBorders) { BorderPanel(model: model) }
      }
      HStack(spacing: 2) {
        FormatToggle(title: "左揃え", symbol: "text.alignleft", isOn: style.alignment == .left) { model.setAlignment(.left) }
        FormatToggle(title: "中央揃え", symbol: "text.aligncenter", isOn: style.alignment == .center) { model.setAlignment(.center) }
        FormatToggle(title: "右揃え", symbol: "text.alignright", isOn: style.alignment == .right) { model.setAlignment(.right) }
        FormatToggle(title: "上揃え", symbol: "align.vertical.top", isOn: style.verticalAlignment == .top) {
          model.setVerticalAlignment(.top)
        }
        FormatToggle(title: "上下中央揃え", symbol: "align.vertical.center", isOn: style.verticalAlignment == .center) {
          model.setVerticalAlignment(.center)
        }
        FormatToggle(title: "下揃え", symbol: "align.vertical.bottom", isOn: (style.verticalAlignment ?? .bottom) == .bottom) {
          model.setVerticalAlignment(.bottom)
        }
        FormatToggle(title: "折り返して全体を表示する（セルの中の改行は option + Return）", symbol: "text.word.spacing", isOn: style.wraps) {
          model.toggle(\.wraps)
        }
      }
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

/// 子を左から並べ、幅が足りなくなったら次の行へ送る
private struct FlowLayout: Layout {
  var spacing: CGFloat
  var lineSpacing: CGFloat

  private func rows(for width: CGFloat, subviews: Subviews) -> [[(index: Int, size: CGSize)]] {
    var rows: [[(index: Int, size: CGSize)]] = [[]]
    var x: CGFloat = 0
    for (index, subview) in subviews.enumerated() {
      let size = subview.sizeThatFits(.unspecified)
      if x > 0, x + size.width > width {
        rows.append([])
        x = 0
      }
      rows[rows.count - 1].append((index, size))
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
    var y = bounds.minY
    for row in rows(for: bounds.width, subviews: subviews) {
      let height = row.map(\.size.height).max() ?? 0
      var x = bounds.minX
      for item in row {
        subviews[item.index].place(at: CGPoint(x: x, y: y + (height - item.size.height) / 2), proposal: ProposedViewSize(item.size))
        x += item.size.width + spacing
      }
      y += height + lineSpacing
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
