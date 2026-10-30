import Foundation
import Testing

@testable import KinkoCore

private func sample() throws -> (Workspace, folder: UUID, file: UUID) {
  var workspace = Workspace()
  let folder = WorkspaceItem.folder("仕事")
  let file = WorkspaceItem.file("議事録.txt", text: "社外秘")
  try workspace.add(folder, to: nil)
  try workspace.add(file, to: folder.id)
  return (workspace, folder.id, file.id)
}

@Test func roundTripThroughVault() throws {
  let (workspace, _, file) = try sample()
  let vault = try UnlockedVault.create(password: "pw", parameters: KDFParameters(memoryKiB: 8, iterations: 1))
  let sealed = try vault.seal(workspace.encoded())
  let opened = try Workspace.decode(UnlockedVault.open(sealed, password: "pw").plaintext)
  #expect(opened == workspace)
  #expect(opened.item(file)?.text == "社外秘")
  // ファイル名も暗号文の中に隠れている
  #expect(sealed.range(of: Data("議事録".utf8)) == nil)
}

@Test func legacyTextVaultBecomesOneFile() throws {
  let workspace = try Workspace.decode(Data("v0.1 のメモ".utf8))
  #expect(workspace.items.count == 1)
  #expect(workspace.items[0].name == "メモ.txt")
  #expect(workspace.items[0].text == "v0.1 のメモ")
  #expect(try Workspace.decode(Data()).items.isEmpty)
}

@Test func newerFormatIsNotTreatedAsText() {
  #expect(throws: WorkspaceError.unsupportedVersion(6)) {
    try Workspace.decode(Data(#"{"kinkoWorkspace":6,"items":[]}"#.utf8))
  }
}

/// 表のない形式 1 も開け、次に保存するときは形式 2 で書く（古い版のアプリに表を消されないように）
@Test func version1OpensAndIsSavedAsCurrent() throws {
  let id = UUID()
  let json = #"{"kinkoWorkspace":1,"items":[{"id":"\#(id.uuidString)","name":"a.md","text":"本文"}]}"#
  let workspace = try Workspace.decode(Data(json.utf8))
  #expect(workspace.items.first?.text == "本文")
  #expect(workspace.items.first?.isSheet == false)
  #expect(workspace.kinkoWorkspace == Workspace.currentVersion)
}

@Test func sheetSurvivesRoundTrip() throws {
  var sheet = Sheet(name: "売上")
  sheet[CellAddress("A1")!] = "りんご"
  sheet[CellAddress("B1")!] = "=1+2"
  sheet.columnWidths[1] = 140
  var workspace = Workspace()
  try workspace.add(.sheet("表.xlsx", workbook: Workbook(sheets: [sheet])), to: nil)
  let decoded = try Workspace.decode(workspace.encoded())
  #expect(decoded == workspace)
  #expect(decoded.items[0].sheet?.sheets[0][CellAddress("B1")!] == "=1+2")
}

@Test func foldersComeFirstInFinderOrder() throws {
  var workspace = Workspace()
  for name in ["b.txt", "file10.txt", "file2.txt"] { try workspace.add(.file(name), to: nil) }
  try workspace.add(.folder("z"), to: nil)
  #expect(workspace.items.map(\.name) == ["z", "b.txt", "file2.txt", "file10.txt"])
}

@Test func newItemsGoNextToSelection() throws {
  let (workspace, folder, file) = try sample()
  #expect(workspace.folderForNewItem(selection: nil) == nil)
  #expect(workspace.folderForNewItem(selection: folder) == folder)
  #expect(workspace.folderForNewItem(selection: file) == folder)
}

@Test func duplicateAndInvalidNamesAreRejected() throws {
  var (workspace, folder, file) = try sample()
  #expect(throws: WorkspaceError.duplicateName("議事録.TXT")) {
    try workspace.add(.file("議事録.TXT"), to: folder)
  }
  for name in ["", "  ", "a/b", ".."] {
    #expect(throws: WorkspaceError.invalidName) { try workspace.rename(file, to: name) }
  }
  // 別のフォルダなら同じ名前でもよい
  try workspace.add(.file("議事録.txt"), to: nil)
  // ファイルの中には作れない
  #expect(throws: WorkspaceError.notAFolder) { try workspace.add(.file("x"), to: file) }
}

@Test func uniqueNameCountsUp() throws {
  var workspace = Workspace()
  #expect(workspace.uniqueName("新規ファイル.txt", in: nil) == "新規ファイル.txt")
  try workspace.add(.file("新規ファイル.txt"), to: nil)
  try workspace.add(.file("新規ファイル 2.txt"), to: nil)
  #expect(workspace.uniqueName("新規ファイル.txt", in: nil) == "新規ファイル 3.txt")
  #expect(workspace.uniqueName("新規フォルダ", in: nil) == "新規フォルダ")
}

@Test func renameKeepsContentAndResorts() throws {
  var (workspace, folder, file) = try sample()
  try workspace.add(.file("b.txt"), to: folder)
  try workspace.rename(file, to: "z.txt")
  #expect(workspace.item(file)?.text == "社外秘")
  #expect(workspace.item(folder)?.children?.map(\.name) == ["b.txt", "z.txt"])
  // 名前を変えずに確定してもエラーにしない
  try workspace.rename(file, to: "z.txt")
}

@Test func removingFolderRemovesContents() throws {
  var (workspace, folder, file) = try sample()
  #expect(workspace.remove(folder)?.name == "仕事")
  #expect(workspace.item(file) == nil)
  #expect(workspace.items.isEmpty)
}

@Test func setTextOnlyChangesFiles() throws {
  var (workspace, folder, file) = try sample()
  workspace.setText("更新", for: file)
  workspace.setText("無視される", for: folder)
  #expect(workspace.item(file)?.text == "更新")
  #expect(workspace.item(folder)?.text == "")
}

@Test func moveBetweenFolders() throws {
  var (workspace, folder, file) = try sample()
  try workspace.move(file, to: nil)
  #expect(workspace.items.map(\.name) == ["仕事", "議事録.txt"])
  #expect(workspace.item(folder)?.children?.isEmpty == true)
  try workspace.move(file, to: folder)
  #expect(workspace.item(folder)?.children?.map(\.name) == ["議事録.txt"])
  #expect(workspace.item(file)?.text == "社外秘")
}

@Test func movingFolderCarriesContents() throws {
  var (workspace, folder, file) = try sample()
  let archive = WorkspaceItem.folder("保管")
  try workspace.add(archive, to: nil)
  try workspace.move(folder, to: archive.id)
  #expect(workspace.folderForNewItem(selection: file) == folder)
  #expect(workspace.item(archive.id)?.children?.map(\.name) == ["仕事"])
}

/// フォルダを自分自身や自分の子孫の中へ入れると木が輪になって壊れるので、拒否する
@Test func cannotMoveFolderIntoItself() throws {
  var (workspace, folder, _) = try sample()
  let child = WorkspaceItem.folder("下")
  try workspace.add(child, to: folder)
  let before = workspace
  #expect(throws: WorkspaceError.cannotMoveIntoItself) { try workspace.move(folder, to: folder) }
  #expect(throws: WorkspaceError.cannotMoveIntoItself) { try workspace.move(folder, to: child.id) }
  #expect(workspace == before)
}

/// 移動先に同じ名前があれば、元の場所に残したままエラーにする
@Test func failedMoveLeavesItemInPlace() throws {
  var (workspace, folder, file) = try sample()
  let rootFile = WorkspaceItem.file("議事録.txt")
  try workspace.add(rootFile, to: nil)
  let before = workspace
  #expect(throws: WorkspaceError.duplicateName("議事録.txt")) { try workspace.move(file, to: nil) }
  // ファイルの中へは入れられない
  #expect(throws: WorkspaceError.notAFolder) { try workspace.move(folder, to: rootFile.id) }
  #expect(workspace == before)
}

@Test func moveToSameFolderChangesNothing() throws {
  var (workspace, folder, file) = try sample()
  let before = workspace
  try workspace.move(file, to: folder)
  try workspace.move(folder, to: nil)
  #expect(workspace == before)
}
