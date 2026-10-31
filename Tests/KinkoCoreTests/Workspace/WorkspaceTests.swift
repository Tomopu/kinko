import Foundation
import Testing

@testable import KinkoCore

@Suite("金庫の中のファイルとフォルダ")
struct WorkspaceTests {
  /// 「仕事」フォルダの中に「議事録.txt」（本文「社外秘」）がある金庫
  private func sample() throws -> (Workspace, folder: UUID, file: UUID) {
    var workspace = Workspace()
    let folder = WorkspaceItem.folder("仕事")
    let file = WorkspaceItem.file("議事録.txt", text: "社外秘")
    try workspace.add(folder, to: nil)
    try workspace.add(file, to: folder.id)
    return (workspace, folder.id, file.id)
  }

  @Test("暗号化して保存し開き直すと元に戻り、ファイル名も暗号文に出てこない")
  func roundTripThroughVault() throws {
    // Given
    let (workspace, _, file) = try sample()
    let vault = try UnlockedVault.create(password: "pw", parameters: KDFParameters(memoryKiB: 8, iterations: 1))

    // When
    let sealed = try vault.seal(workspace.encoded())
    let opened = try Workspace.decode(UnlockedVault.open(sealed, password: "pw").plaintext)

    // Then
    #expect(opened == workspace)
    #expect(opened.item(file)?.text == "社外秘")
    #expect(sealed.range(of: Data("議事録".utf8)) == nil)
  }

  @Test("v0.1 の文字だけの金庫は「メモ.txt」1 つとして開く")
  func legacyTextVaultBecomesOneFile() throws {
    // Given / When
    let workspace = try Workspace.decode(Data("v0.1 のメモ".utf8))

    // Then
    #expect(workspace.items.count == 1)
    #expect(workspace.items[0].name == "メモ.txt")
    #expect(workspace.items[0].text == "v0.1 のメモ")
  }

  @Test("空のデータは空の金庫として開く")
  func emptyDataIsEmptyWorkspace() throws {
    // Given / When / Then
    #expect(try Workspace.decode(Data()).items.isEmpty)
  }

  @Test("新しすぎる形式は文字として開かず、対応していないと伝える")
  func newerFormatIsNotTreatedAsText() {
    // Given / When / Then
    #expect(throws: WorkspaceError.unsupportedVersion(7)) {
      try Workspace.decode(Data(#"{"kinkoWorkspace":7,"items":[]}"#.utf8))
    }
  }

  /// 古い版のアプリに表を消されないように
  @Test("表のない形式 1 も開け、次に保存するときは今の形式で書く")
  func version1OpensAndIsSavedAsCurrent() throws {
    // Given
    let id = UUID()
    let json = #"{"kinkoWorkspace":1,"items":[{"id":"\#(id.uuidString)","name":"a.md","text":"本文"}]}"#

    // When
    let workspace = try Workspace.decode(Data(json.utf8))

    // Then
    #expect(workspace.items.first?.text == "本文")
    #expect(workspace.items.first?.isSheet == false)
    #expect(workspace.kinkoWorkspace == Workspace.currentVersion)
  }

  @Test("表は入力・数式・列の幅ごと保存して読み戻せる")
  func sheetSurvivesRoundTrip() throws {
    // Given
    var sheet = Sheet(name: "売上", cells: ["A1": "りんご", "B1": "=1+2"])
    sheet.columnWidths[1] = 140
    var workspace = Workspace()
    try workspace.add(.sheet("表.xlsx", workbook: Workbook(sheets: [sheet])), to: nil)

    // When
    let decoded = try Workspace.decode(workspace.encoded())

    // Then
    #expect(decoded == workspace)
    #expect(decoded.items[0].sheet?.sheets[0]["B1"] == "=1+2")
  }

  @Test("フォルダを先に、名前は Finder と同じ順（数は大きさの順）に並べる")
  func foldersComeFirstInFinderOrder() throws {
    // Given
    var workspace = Workspace()

    // When
    for name in ["b.txt", "file10.txt", "file2.txt"] { try workspace.add(.file(name), to: nil) }
    try workspace.add(.folder("z"), to: nil)

    // Then
    #expect(workspace.items.map(\.name) == ["z", "b.txt", "file2.txt", "file10.txt"])
  }

  @Test("新しい項目は、選んだフォルダか、選んだファイルと同じフォルダに作る")
  func newItemsGoNextToSelection() throws {
    // Given
    let (workspace, folder, file) = try sample()

    // When / Then: 何も選んでいなければ一番上
    #expect(workspace.folderForNewItem(selection: nil) == nil)
    #expect(workspace.folderForNewItem(selection: folder) == folder)
    #expect(workspace.folderForNewItem(selection: file) == folder)
  }

  @Test("同じフォルダには大文字小文字だけ違う名前も置けないが、別のフォルダなら置ける")
  func duplicateNamesAreRejected() throws {
    // Given
    var (workspace, folder, _) = try sample()

    // When / Then
    #expect(throws: WorkspaceError.duplicateName("議事録.TXT")) {
      try workspace.add(.file("議事録.TXT"), to: folder)
    }
    try workspace.add(.file("議事録.txt"), to: nil)
  }

  @Test("空・空白だけ・/ を含む・.. の名前には変えられない", arguments: ["", "  ", "a/b", ".."])
  func invalidNamesAreRejected(name: String) throws {
    // Given
    var (workspace, _, file) = try sample()

    // When / Then
    #expect(throws: WorkspaceError.invalidName) { try workspace.rename(file, to: name) }
  }

  @Test("ファイルの中には項目を作れない")
  func cannotAddIntoFile() throws {
    // Given
    var (workspace, _, file) = try sample()

    // When / Then
    #expect(throws: WorkspaceError.notAFolder) { try workspace.add(.file("x"), to: file) }
  }

  @Test("同じ名前があれば「 2」「 3」と番号を付けた名前を勧める")
  func uniqueNameCountsUp() throws {
    // Given: 「新規ファイル.txt」と「新規ファイル 2.txt」がある
    var workspace = Workspace()
    #expect(workspace.uniqueName("新規ファイル.txt", in: nil) == "新規ファイル.txt")
    try workspace.add(.file("新規ファイル.txt"), to: nil)
    try workspace.add(.file("新規ファイル 2.txt"), to: nil)

    // When / Then
    #expect(workspace.uniqueName("新規ファイル.txt", in: nil) == "新規ファイル 3.txt")
    #expect(workspace.uniqueName("新規フォルダ", in: nil) == "新規フォルダ")
  }

  @Test("名前を変えても中身は残り、並び直す。同じ名前のまま確定してもエラーにしない")
  func renameKeepsContentAndResorts() throws {
    // Given: 「仕事」の中に「b.txt」も足す
    var (workspace, folder, file) = try sample()
    try workspace.add(.file("b.txt"), to: folder)

    // When
    try workspace.rename(file, to: "z.txt")

    // Then
    #expect(workspace.item(file)?.text == "社外秘")
    #expect(workspace.item(folder)?.children?.map(\.name) == ["b.txt", "z.txt"])
    try workspace.rename(file, to: "z.txt")
  }

  @Test("フォルダを消すと中身も消える")
  func removingFolderRemovesContents() throws {
    // Given
    var (workspace, folder, file) = try sample()

    // When
    let removed = workspace.remove(folder)

    // Then
    #expect(removed?.name == "仕事")
    #expect(workspace.item(file) == nil)
    #expect(workspace.items.isEmpty)
  }

  @Test("PDF は中身のバイト列ごと保存して読み戻せ、本文の書き込みは無視する")
  func pdfSurvivesSave() throws {
    // Given
    let bytes = Data("%PDF-1.7\n".utf8) + Data([0x00, 0xFF, 0x80])
    var workspace = Workspace()
    let pdf = WorkspaceItem.pdf("資料.pdf", data: bytes)
    try workspace.add(pdf, to: nil)

    // When
    workspace.setText("無視される", for: pdf.id)
    let decoded = try Workspace.decode(workspace.encoded())

    // Then
    #expect(decoded.item(pdf.id)?.data == bytes)
    #expect(decoded.item(pdf.id)?.isPDF == true)
    #expect(decoded.item(pdf.id)?.text == "")
  }

  @Test("本文を書き換えられるのはファイルだけで、フォルダへの書き込みは無視する")
  func setTextOnlyChangesFiles() throws {
    // Given
    var (workspace, folder, file) = try sample()

    // When
    workspace.setText("更新", for: file)
    workspace.setText("無視される", for: folder)

    // Then
    #expect(workspace.item(file)?.text == "更新")
    #expect(workspace.item(folder)?.text == "")
  }

  @Test("ファイルをフォルダの外へ出し、また戻せる")
  func moveBetweenFolders() throws {
    // Given
    var (workspace, folder, file) = try sample()

    // When: 一番上へ出す
    try workspace.move(file, to: nil)

    // Then
    #expect(workspace.items.map(\.name) == ["仕事", "議事録.txt"])
    #expect(workspace.item(folder)?.children?.isEmpty == true)

    // When: フォルダへ戻す
    try workspace.move(file, to: folder)

    // Then: 中身もそのまま
    #expect(workspace.item(folder)?.children?.map(\.name) == ["議事録.txt"])
    #expect(workspace.item(file)?.text == "社外秘")
  }

  @Test("フォルダを動かすと中身も一緒に動く")
  func movingFolderCarriesContents() throws {
    // Given: 一番上に「保管」フォルダ
    var (workspace, folder, file) = try sample()
    let archive = WorkspaceItem.folder("保管")
    try workspace.add(archive, to: nil)

    // When
    try workspace.move(folder, to: archive.id)

    // Then
    #expect(workspace.folderForNewItem(selection: file) == folder)
    #expect(workspace.item(archive.id)?.children?.map(\.name) == ["仕事"])
  }

  /// 木が輪になって壊れるので
  @Test("フォルダを自分自身や自分の子孫の中へは動かせず、何も変わらない")
  func cannotMoveFolderIntoItself() throws {
    // Given: 「仕事」の中に「下」フォルダ
    var (workspace, folder, _) = try sample()
    let child = WorkspaceItem.folder("下")
    try workspace.add(child, to: folder)
    let before = workspace

    // When / Then
    #expect(throws: WorkspaceError.cannotMoveIntoItself) { try workspace.move(folder, to: folder) }
    #expect(throws: WorkspaceError.cannotMoveIntoItself) { try workspace.move(folder, to: child.id) }
    #expect(workspace == before)
  }

  @Test("移動先に同じ名前があるときや、ファイルの中へは動かせず、元の場所に残る")
  func failedMoveLeavesItemInPlace() throws {
    // Given: 一番上にも「議事録.txt」
    var (workspace, folder, file) = try sample()
    let rootFile = WorkspaceItem.file("議事録.txt")
    try workspace.add(rootFile, to: nil)
    let before = workspace

    // When / Then
    #expect(throws: WorkspaceError.duplicateName("議事録.txt")) { try workspace.move(file, to: nil) }
    #expect(throws: WorkspaceError.notAFolder) { try workspace.move(folder, to: rootFile.id) }
    #expect(workspace == before)
  }

  @Test("今と同じフォルダへ動かしても何も変わらない")
  func moveToSameFolderChangesNothing() throws {
    // Given
    var (workspace, folder, file) = try sample()
    let before = workspace

    // When
    try workspace.move(file, to: folder)
    try workspace.move(folder, to: nil)

    // Then
    #expect(workspace == before)
  }
}
