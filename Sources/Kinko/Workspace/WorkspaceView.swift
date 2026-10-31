import KinkoCore
import SwiftUI

/// 解錠後の画面。左にフォルダとファイルの一覧、右に選んだファイルのエディタ
struct WorkspaceView: View {
  @Environment(VaultSession.self) private var session
  let url: URL

  @State private var namePrompt: NamePrompt?
  @State private var nameDraft = ""
  @State private var pendingDeletion: WorkspaceItem?
  @State private var isConfirmingLock = false
  @State private var isRootExpanded = true
  @State private var showsMarkdownSyntax = false

  var body: some View {
    @Bindable var session = session
    NavigationSplitView {
      sidebar
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 360)
    } detail: {
      detail
    }
    .navigationTitle(url.lastPathComponent + (session.isDirty ? " — 未保存" : ""))
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        if let id = session.selection, session.workspace.item(id)?.isMarkdown == true {
          Toggle("記号を表示", systemImage: "number", isOn: $showsMarkdownSyntax)
            .hoverLabel("Markdown の記号（# や ** など）をすべての行で表示する")
        }
        // macOS には決まった保存アイコンがなく、矢印のアイコンはダウンロードに見えるので文字にする
        Button("保存") { session.save() }
          .disabled(!session.isDirty)
          .hoverLabel("暗号化して保存（⌘S）")
        Button("ロック", systemImage: "lock") { requestLock() }
          .hoverLabel("ロック（⌘L）")
      }
    }
    .alert(namePrompt?.title ?? "", isPresented: isPromptingName) {
      TextField("名前", text: $nameDraft)
      Button("キャンセル", role: .cancel) {}
      Button(namePrompt?.confirmLabel ?? "OK", action: commitName)
    }
    .confirmationDialog(
      "「\(pendingDeletion?.name ?? "")」を削除しますか？",
      isPresented: isConfirmingDeletion, presenting: pendingDeletion
    ) { item in
      Button("削除", role: .destructive) { session.remove(item.id) }
    } message: { item in
      Text(item.isFolder ? "フォルダの中身もすべて削除されます。保存すると元に戻せません。" : "保存すると元に戻せません。")
    }
    .confirmationDialog("保存していない変更があります", isPresented: $isConfirmingLock) {
      Button("保存してロック") {
        session.save()
        if !session.isDirty { session.lock() }
      }
      Button("保存せずにロック", role: .destructive) { session.lock() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .kinkoNewFile)) { _ in promptNewFile() }
    .onReceive(NotificationCenter.default.publisher(for: .kinkoNewFolder)) { _ in promptNewFolder() }
    .onReceive(NotificationCenter.default.publisher(for: .kinkoNewSheet)) { _ in promptNewSheet() }
    .onReceive(NotificationCenter.default.publisher(for: .kinkoLock)) { _ in requestLock() }
  }

  // MARK: - サイドバー

  private var sidebar: some View {
    @Bindable var session = session
    // 一覧の空いた所へのドロップはリスト（NSOutlineView）に吸収されて届かないので、
    // 金庫そのものを表す行を一番上に置き、そこを一番上の階層への移動先にする
    return List(selection: $session.selection) {
      DisclosureGroup(isExpanded: $isRootExpanded) {
        OutlineGroup(session.workspace.items, children: \.children) { item in
          SidebarRow(item: item)
        }
      } label: {
        RootRow(title: url.deletingPathExtension().lastPathComponent)
      }
    }
    .contextMenu(forSelectionType: WorkspaceItem.ID.self) { ids in
      if let id = ids.first, let item = session.workspace.item(id) {
        Button("名前を変更…") { promptRename(item) }
        Button("書き出す…") {
          session.selection = id
          session.exportSelection()
        }
        Button("削除…", role: .destructive) { pendingDeletion = item }
        Divider()
      }
      Button("新規ファイル…") {
        session.selection = ids.first
        promptNewFile()
      }
      Button("新規の表…") {
        session.selection = ids.first
        promptNewSheet()
      }
      Button("新規フォルダ…") {
        session.selection = ids.first
        promptNewFolder()
      }
      Divider()
      Button("読み込む…") {
        session.selection = ids.first
        session.importFiles()
      }
    }
    .onDeleteCommand {
      if let id = session.selection { pendingDeletion = session.workspace.item(id) }
    }
    .overlay {
      if session.workspace.items.isEmpty {
        ContentUnavailableView("空の金庫", systemImage: "tray", description: Text("下のボタンでファイルを追加できます。"))
      }
    }
    .safeAreaInset(edge: .bottom) {
      HStack(spacing: 4) {
        Button("新規ファイル", systemImage: "doc.badge.plus", action: promptNewFile)
          .hoverLabel("新規ファイル（⌘N）")
        Button("新規の表", systemImage: "tablecells.badge.ellipsis", action: promptNewSheet)
          .hoverLabel("新規の表（⌥⌘N）")
        Button("新規フォルダ", systemImage: "folder.badge.plus", action: promptNewFolder)
          .hoverLabel("新規フォルダ（⇧⌘N）")
        Button("読み込む", systemImage: "square.and.arrow.down") { session.importFiles() }
          .hoverLabel("ファイルやフォルダを金庫へ読み込む（⇧⌘I）")
        Spacer()
        SettingsLink {
          Label("設定", systemImage: "gearshape")
        }
        .hoverLabel("設定（⌘,）")
      }
      .labelStyle(.iconOnly)
      .buttonStyle(.borderless)
      .font(.system(size: 14))
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
    }
  }

  // MARK: - エディタ

  @ViewBuilder
  private var detail: some View {
    if let id = session.selection, let item = session.workspace.item(id), !item.isFolder {
      VStack(spacing: 0) {
        // エディタに外側の余白を付けると、ツールバーの帯がエディタの幅に縮んで段差になる。余白は NSTextView の内側に取る
        let text = Binding(get: { session.text(of: id) }, set: { session.setText($0, of: id) })
        Group {
          if item.isSheet {
            SheetEditor(workbook: Binding(get: { session.workbook(of: id) }, set: { session.setWorkbook($0, of: id) }))
          } else if let data = item.data {
            PDFViewer(data: data)
          } else if item.isMarkdown {
            MarkdownEditor(text: text, showsSyntax: showsMarkdownSyntax)
          } else {
            PlainTextEditor(text: text)
          }
        }
        .id(id)
        errorBar
      }
      .navigationSubtitle(item.name)
    } else {
      ContentUnavailableView("ファイルを選んでください", systemImage: "doc.text", description: Text("左の一覧からファイルを選ぶと、ここで編集できます。"))
        .safeAreaInset(edge: .bottom) { errorBar }
    }
  }

  @ViewBuilder
  private var errorBar: some View {
    if let message = session.errorMessage {
      Text(message)
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
    }
  }

  // MARK: - 操作

  private func promptNewFile() {
    nameDraft = session.suggestedName("新規ファイル.md")
    namePrompt = .newFile
  }

  private func promptNewSheet() {
    nameDraft = session.suggestedName("新規の表.xlsx")
    namePrompt = .newSheet
  }

  private func promptNewFolder() {
    nameDraft = session.suggestedName("新規フォルダ")
    namePrompt = .newFolder
  }

  private func promptRename(_ item: WorkspaceItem) {
    nameDraft = item.name
    namePrompt = .rename(item.id)
  }

  private func commitName() {
    switch namePrompt {
    case .newFile:
      // 表の拡張子を付けたら表として作る
      let isSheet = FileTransfer.sheetExtensions.contains((nameDraft as NSString).pathExtension.lowercased())
      session.addItem(isSheet ? .sheet(nameDraft) : .file(nameDraft))
    case .newSheet: session.addItem(.sheet(nameDraft))
    case .newFolder: session.addItem(.folder(nameDraft))
    case .rename(let id): session.rename(id, to: nameDraft)
    case nil: break
    }
    namePrompt = nil
  }

  private func requestLock() {
    if session.isDirty { isConfirmingLock = true } else { session.lock() }
  }

  private var isPromptingName: Binding<Bool> {
    Binding(get: { namePrompt != nil }, set: { if !$0 { namePrompt = nil } })
  }

  private var isConfirmingDeletion: Binding<Bool> {
    Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
  }
}

/// 金庫そのものを表す一番上の行。ここへ落とすと一番上の階層へ移す
private struct RootRow: View {
  @Environment(VaultSession.self) private var session
  let title: String

  @State private var isTargeted = false

  var body: some View {
    Label(title, systemImage: "lock.shield")
      .fontWeight(.semibold)
      .lineLimit(1)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .dropDestination(for: ItemReference.self) { references, _ in
        guard let reference = references.first else { return false }
        return session.move(reference.id, to: nil)
      } isTargeted: { isTargeted = $0 }
      .background {
        if isTargeted {
          RoundedRectangle(cornerRadius: 6)
            .fill(Color.accentColor.opacity(0.25))
            .padding(-4)
        }
      }
  }
}

/// サイドバーの 1 行。ドラッグでき、フォルダの上に落とせばその中へ、ファイルの上に落とせばそのファイルと同じフォルダへ移す
private struct SidebarRow: View {
  @Environment(VaultSession.self) private var session
  let item: WorkspaceItem

  @State private var isTargeted = false

  var body: some View {
    Label(item.name, systemImage: item.symbolName)
      .lineLimit(1)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .draggable(ItemReference(id: item.id)) {
        Label(item.name, systemImage: item.symbolName)
          .padding(6)
      }
      .dropDestination(for: ItemReference.self) { references, _ in
        guard let reference = references.first else { return false }
        return session.move(reference.id, to: session.workspace.folderForNewItem(selection: item.id))
      } isTargeted: { targeted in
        isTargeted = targeted && item.isFolder
      }
      .background {
        if isTargeted {
          RoundedRectangle(cornerRadius: 6)
            .fill(Color.accentColor.opacity(0.25))
            .padding(-4)
        }
      }
  }
}

private enum NamePrompt: Equatable {
  case newFile
  case newSheet
  case newFolder
  case rename(WorkspaceItem.ID)

  var title: String {
    switch self {
    case .newFile: "新規ファイル"
    case .newSheet: "新規の表"
    case .newFolder: "新規フォルダ"
    case .rename: "名前を変更"
    }
  }

  var confirmLabel: String {
    switch self {
    case .newFile, .newSheet, .newFolder: "作成"
    case .rename: "変更"
    }
  }
}

extension Notification.Name {
  static let kinkoNewFile = Notification.Name("kinkoNewFile")
  static let kinkoNewFolder = Notification.Name("kinkoNewFolder")
  static let kinkoNewSheet = Notification.Name("kinkoNewSheet")
  static let kinkoLock = Notification.Name("kinkoLock")
}

extension WorkspaceItem {
  var isMarkdown: Bool {
    ["md", "markdown"].contains((name as NSString).pathExtension.lowercased())
  }

  /// 中に線のない、形だけのアイコンにする（一覧が細かい模様だらけにならないように）
  var symbolName: String {
    if isFolder { return "folder" }
    if isPDF { return "book.closed" }
    return isSheet ? "tablecells" : "doc"
  }
}
