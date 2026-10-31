import KinkoCore
import SwiftUI

/// 「パスワードだけ」と「この Mac 専用」の違いの表。current の列の見出しに色を付け、もう一方の列を薄くする
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
  }

  private func header(_ title: String, systemImage: String, isCurrent: Bool) -> some View {
    Label(title, systemImage: systemImage)
      .fontWeight(.semibold)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 3)
      .padding(.horizontal, 4)
      .background(isCurrent ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 5))
      .padding(.horizontal, -4)
  }

  private func cell(_ text: String, isOther: Bool) -> some View {
    Text(text)
      .foregroundStyle(isOther ? .secondary : .primary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
