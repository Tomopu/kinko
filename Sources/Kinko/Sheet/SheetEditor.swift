import KinkoCore
import SwiftUI

/// 表のエディタ。上に書式バーと数式バー、真ん中にグリッド、下にシートの切り替えと集計
struct SheetEditor: View {
  @Binding var workbook: Workbook

  /// 作るときに全セルを計算するので、親が描き直されるたびに作り直さないよう、表示されたときに一度だけ作る
  @State private var model: SheetEditorModel?
  @State private var renamingSheet: Int?
  @State private var sheetNameDraft = ""
  @State private var removingSheet: Int?

  var body: some View {
    Group {
      if let model {
        VStack(spacing: 0) {
          FormatBar(model: model)
          Divider()
          FormulaBar(model: model)
          Divider()
          SheetGrid(model: model)
          Divider()
          sheetTabs(model)
        }
        .onChange(of: workbook) { _, new in model.update(from: new) }
      } else {
        Color(nsColor: .textBackgroundColor)
      }
    }
    .onAppear {
      let model = SheetEditorModel(workbook: workbook)
      let binding = $workbook
      model.onChange = { binding.wrappedValue = $0 }
      self.model = model
    }
  }

  private func sheetTabs(_ model: SheetEditorModel) -> some View {
    HStack(spacing: 2) {
      ForEach(model.workbook.sheets.indices, id: \.self) { index in
        let isSelected = index == model.sheetIndex
        Button(model.workbook.sheets[index].name) { model.selectSheet(index) }
          .buttonStyle(.plain)
          .fontWeight(isSelected ? .semibold : .regular)
          .padding(.horizontal, 10)
          .padding(.vertical, 3)
          .background(isSelected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 5))
          .contextMenu {
            Button("名前を変更…") {
              sheetNameDraft = model.workbook.sheets[index].name
              renamingSheet = index
            }
            Button("削除…", role: .destructive) { removingSheet = index }
              .disabled(model.workbook.sheets.count == 1)
          }
      }
      Button("シートを追加", systemImage: "plus") { model.addSheet() }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .help("シートを追加")
      Spacer()
      if let message = model.errorMessage {
        Text(message).foregroundStyle(.red).lineLimit(1)
      } else if let summary = model.summary {
        // Excel の下のバーと同じ並び
        HStack(spacing: 14) {
          if summary.numbers > 0 { Text("平均: \(Self.summaryText(summary.average))") }
          Text("データの個数: \(summary.count)")
          if summary.numbers > 0 { Text("合計: \(Self.summaryText(summary.sum))") }
        }
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .textSelection(.enabled)
      }
    }
    .font(.callout)
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .alert("シート名を変更", isPresented: Binding(get: { renamingSheet != nil }, set: { if !$0 { renamingSheet = nil } })) {
      TextField("名前", text: $sheetNameDraft)
      Button("キャンセル", role: .cancel) {}
      Button("変更") {
        if let index = renamingSheet { model.renameSheet(index, to: sheetNameDraft) }
      }
    }
    .confirmationDialog(
      "シート「\(removingSheet.map { model.workbook.sheets[min($0, model.workbook.sheets.count - 1)].name } ?? "")」を削除しますか？",
      isPresented: Binding(get: { removingSheet != nil }, set: { if !$0 { removingSheet = nil } })
    ) {
      Button("削除", role: .destructive) {
        if let index = removingSheet { model.removeSheet(index) }
      }
    } message: {
      Text("このシートを参照している数式は #REF! になります。⌘Z で取り消せます。")
    }
  }
}

extension SheetEditor {
  /// 集計の数。桁区切りを入れ、小数は 4 桁まで
  static func summaryText(_ number: Double) -> String {
    let decimals = number == number.rounded() ? 0 : 4
    var text = NumberFormat.number(decimals: decimals, grouping: true).format(number) ?? ""
    if text.contains(".") {
      while text.hasSuffix("0") { text.removeLast() }
      if text.hasSuffix(".") { text.removeLast() }
    }
    return text
  }
}

/// 選んでいるセルの位置と、入力（数式ならその式）。ここで直して Return でも入力できる。右端に検索欄
private struct FormulaBar: View {
  @Bindable var model: SheetEditorModel
  @State private var searchText = ""
  @FocusState private var isSearching: Bool

  var body: some View {
    HStack(spacing: 8) {
      Text(model.active.description)
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(.secondary)
        .frame(width: 64)
      Divider().frame(height: 16)
      Image(systemName: "function")
        .foregroundStyle(.secondary)
      TextField("", text: $model.formulaText)
        .textFieldStyle(.plain)
        .font(.system(size: 13).monospacedDigit())
        .autocorrectionDisabled()
        .onSubmit { model.commitFormulaBar() }
      search
    }
    .padding(.horizontal, 10)
    .frame(height: 30)
  }

  private var search: some View {
    HStack(spacing: 4) {
      Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
      TextField("検索（⌘F）", text: $searchText)
        .textFieldStyle(.plain)
        .focused($isSearching)
        .onSubmit { model.find(searchText) }
      // ⌘F で検索欄へ移る。透明なボタンにショートカットだけを付ける（hidden にするとショートカットも効かなくなる）
      Button("検索") { isSearching = true }
        .keyboardShortcut("f")
        .opacity(0)
        .frame(width: 0)
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
    .frame(width: 150)
  }
}

private struct SheetGrid: NSViewRepresentable {
  let model: SheetEditorModel

  func makeNSView(context: Context) -> SheetGridView {
    let view = SheetGridView(model: model)
    model.onDisplayChange = { [weak view] in view?.reload() }
    model.onReveal = { [weak view] in view?.cells.scrollToActive() }
    DispatchQueue.main.async { view.window?.makeFirstResponder(view.cells) }
    return view
  }

  func updateNSView(_ view: SheetGridView, context: Context) {}
}
