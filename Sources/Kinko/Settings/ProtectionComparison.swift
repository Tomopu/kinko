import KinkoCore
import SwiftUI

/// 「パスワードだけ」と「この Mac 専用」の違いの表。current の列を見出しから一番下まで 1 枚の色で囲み、もう一方の列を薄くする
struct ProtectionComparison: View {
  var current: UnlockedVault.Protection?

  private static let rows: [(topic: String, password: String, deviceBound: String)] = [
    ("開くのに要るもの", "パスワード", "パスワードと、この Mac"),
    ("ファイルがほかの Mac へコピーされたら", "パスワードを当てられると開かれる", "パスワードを知られても開けない"),
    ("自分のほかの Mac で開く", "できる", "できない"),
    ("この Mac が壊れたり、失くしたりしたら", "ほかの Mac でパスワードで開ける", "復旧コードでだけ開ける"),
    ("間違え続けたら削除する設定", "この Mac の金庫だけが消える（コピーは残る）", "コピーやバックアップもパスワードでは開けなくなる"),
    ("控えておくもの", "パスワード", "パスワードと復旧コード"),
  ]

  var body: some View {
    Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 6) {
      GridRow {
        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
        header("パスワードだけ", systemImage: "key", isCurrent: current == .password)
        header("この Mac 専用", systemImage: "laptopcomputer", isCurrent: current == .deviceBound)
      }
      ForEach(Self.rows, id: \.topic) { row in
        Divider()
        GridRow {
          Text(row.topic).foregroundStyle(.secondary)
          cell(row.password, isOther: current == .deviceBound)
          cell(row.deviceBound, isOther: current == .password)
        }
      }
    }
    .font(.callout)
    // 今の守り方の列のセルの範囲を集め、その外枠に 1 枚の背景を敷く（行の区切り線をまたいで続く）
    .backgroundPreferenceValue(CurrentColumnBounds.self) { anchors in
      GeometryReader { proxy in
        if let first = anchors.first {
          // 右は区切り線の端にそろえ、左と上下だけ文字から少し離す
          let bounds = anchors.dropFirst().reduce(proxy[first]) { $0.union(proxy[$1]) }
          let rect = CGRect(x: bounds.minX - 6, y: bounds.minY - 4, width: bounds.width + 6, height: bounds.height + 8)
          RoundedRectangle(cornerRadius: 6)
            .fill(Color.accentColor.opacity(0.18))
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
        }
      }
    }
  }

  private func header(_ title: String, systemImage: String, isCurrent: Bool) -> some View {
    Label(title, systemImage: systemImage)
      .fontWeight(.semibold)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 3)
      .anchorPreference(key: CurrentColumnBounds.self, value: .bounds) { isCurrent ? [$0] : [] }
  }

  private func cell(_ text: String, isOther: Bool) -> some View {
    Text(text)
      .foregroundStyle(isOther ? .secondary : .primary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .anchorPreference(key: CurrentColumnBounds.self, value: .bounds) { isOther || current == nil ? [] : [$0] }
  }
}

/// 今の守り方の列にあるセルの範囲
private struct CurrentColumnBounds: PreferenceKey {
  static let defaultValue: [Anchor<CGRect>] = []
  static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) { value += nextValue() }
}
