import KinkoCore
import SwiftUI

/// 罫線の画面：線の種類と色を選んでから、引く場所を押す（Excel の「その他の罫線」と同じ順番）
struct BorderPanel: View {
  @Bindable var model: SheetEditorModel

  /// よく使う順
  private static let styles: [(BorderStyle, String)] = [
    (.thin, "細線"), (.medium, "中線"), (.thick, "太線"), (.double, "二重線"),
    (.hair, "極細線"), (.dotted, "点線"), (.dashed, "破線"), (.mediumDashed, "太い破線"),
    (.dashDot, "一点鎖線"), (.mediumDashDot, "太い一点鎖線"), (.dashDotDot, "二点鎖線"), (.mediumDashDotDot, "太い二点鎖線"),
    (.slantDashDot, "斜め一点鎖線"),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("罫線").font(.headline)

      Text("線の種類").font(.subheadline).foregroundStyle(.secondary)
      LazyVGrid(columns: [GridItem(.fixed(150)), GridItem(.fixed(150))], alignment: .leading, spacing: 4) {
        ForEach(Self.styles, id: \.0) { style, name in
          let isSelected = model.borderLine.style == style
          Button {
            model.borderLine.style = style
          } label: {
            HStack(spacing: 8) {
              LineSample(line: BorderLine(style: style, color: model.borderLine.color)).frame(width: 44, height: 12)
              Text(name).font(.callout)
              Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isSelected ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }

      Text("線の色").font(.subheadline).foregroundStyle(.secondary)
      HStack(spacing: 6) {
        Button("自動") { model.borderLine.color = nil }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .background(model.borderLine.color == nil ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 5))
        ForEach(["C00000", "FF0000", "FFC000", "00B050", "0070C0", "7030A0", "808080"], id: \.self) { hex in
          let color = CellColor(hex: hex)!
          Button {
            model.borderLine.color = color
          } label: {
            RoundedRectangle(cornerRadius: 4)
              .fill(Color(nsColor: color.nsColor))
              .frame(width: 20, height: 20)
              .overlay(
                RoundedRectangle(cornerRadius: 4)
                  .strokeBorder(Color.primary.opacity(model.borderLine.color == color ? 0.9 : 0.15), lineWidth: model.borderLine.color == color ? 2 : 1))
          }
          .buttonStyle(.plain)
        }
      }

      Text("引く場所（選んだ範囲に対して）").font(.subheadline).foregroundStyle(.secondary)
      LazyVGrid(columns: Array(repeating: GridItem(.fixed(58), spacing: 6), count: 5), spacing: 8) {
        ForEach(SheetEditorModel.BorderPlacement.allCases, id: \.self) { placement in
          Button {
            model.setBorders(placement)
          } label: {
            VStack(spacing: 3) {
              PlacementIcon(placement: placement).frame(width: 26, height: 26)
              Text(placement.title).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(width: 58)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .hoverLabel(placement.title)
        }
      }
    }
    .padding(14)
  }
}

/// 線の見本。表と同じ太さ・模様で描く
private struct LineSample: View {
  let line: BorderLine

  var body: some View {
    Canvas { context, size in
      let (width, dash) = SheetCellsView.pattern(of: line.style)
      let color = line.color.map { Color(nsColor: $0.nsColor) } ?? .primary
      let offsets: [CGFloat] = line.style == .double ? [-1.5, 1.5] : [0]
      for offset in offsets {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height / 2 + offset))
        path.addLine(to: CGPoint(x: size.width, y: size.height / 2 + offset))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, dash: dash))
      }
    }
  }
}

/// 罫線を引く場所の絵。2×2 のセルのうち、引く線を濃く描く
private struct PlacementIcon: View {
  let placement: SheetEditorModel.BorderPlacement

  var body: some View {
    Canvas { context, size in
      let w = size.width, h = size.height
      let outer = [
        ("top", CGPoint(x: 0, y: 0.5), CGPoint(x: w, y: 0.5)), ("bottom", CGPoint(x: 0, y: h - 0.5), CGPoint(x: w, y: h - 0.5)),
        ("left", CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: h)), ("right", CGPoint(x: w - 0.5, y: 0), CGPoint(x: w - 0.5, y: h)),
      ]
      let inner = [
        ("horizontal", CGPoint(x: 0, y: h / 2), CGPoint(x: w, y: h / 2)), ("vertical", CGPoint(x: w / 2, y: 0), CGPoint(x: w / 2, y: h)),
      ]
      for (name, a, b) in outer + inner {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        let on = isOn(name)
        context.stroke(
          path, with: .color(on ? .primary : .secondary.opacity(0.35)),
          style: StrokeStyle(lineWidth: on ? 2 : 1, dash: on ? [] : [2, 2]))
      }
    }
  }

  private func isOn(_ name: String) -> Bool {
    switch placement {
    case .grid: true
    case .outline: ["top", "bottom", "left", "right"].contains(name)
    case .inside: ["horizontal", "vertical"].contains(name)
    case .insideHorizontal: name == "horizontal"
    case .insideVertical: name == "vertical"
    case .top: name == "top"
    case .bottom: name == "bottom"
    case .left: name == "left"
    case .right: name == "right"
    case .none: false
    }
  }
}
