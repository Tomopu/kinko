import Foundation

/// 金庫の中身。フォルダとファイルの木を JSON にして、まるごと 1 つの暗号文にする。
/// ファイル名・ファイル数・各ファイルの大きさも暗号文の中に隠れる
/// （ファイルごとに暗号化してディスクに並べる方式だと、これらは外から見えてしまう）
public struct Workspace: Codable, Equatable, Sendable {
  /// 2 で表（WorkspaceItem.sheet）が、3 でセルの書式（Sheet.styles）が、4 で折り返し・縦の配置・行の高さが、
  /// 5 で罫線の種類と色が、6 で PDF（WorkspaceItem.data）とフォントの種類・大きさが加わった
  /// （形式 5 までのアプリは PDF を空のテキストとして読み、保存すると中身を落とす）
  public static let currentVersion = 6

  /// 中身が Kinko のワークスペースであることと、その形式のバージョン
  public var kinkoWorkspace = Workspace.currentVersion
  public var items: [WorkspaceItem]

  public init(items: [WorkspaceItem] = []) {
    self.items = items.sortedForDisplay()
  }

  // MARK: - 読み書き

  public func encoded() throws -> Data {
    try JSONEncoder().encode(self)
  }

  /// 復号した本文からワークスペースを作る。
  /// v0.1 の金庫は本文がただのテキストなので、1 つのファイルとして取り込む
  public static func decode(_ plaintext: Data) throws -> Workspace {
    if plaintext.isEmpty { return Workspace() }
    if let probe = try? JSONDecoder().decode(VersionProbe.self, from: plaintext) {
      // 知らない新しい形式を開いて保存すると、知らない中身（古い版にとっての表など）を落として壊すので開かない
      guard (1...currentVersion).contains(probe.kinkoWorkspace) else {
        throw WorkspaceError.unsupportedVersion(probe.kinkoWorkspace)
      }
      var workspace = try JSONDecoder().decode(Workspace.self, from: plaintext)
      // 次に保存するときは今の形式で書く。古い版のアプリはこれを開かなくなり、表を消さずに済む
      workspace.kinkoWorkspace = currentVersion
      return workspace
    }
    return Workspace(items: [.file("メモ.txt", text: String(decoding: plaintext, as: UTF8.self))])
  }

  private struct VersionProbe: Decodable {
    var kinkoWorkspace: Int
  }

  // MARK: - 探す

  public func item(_ id: UUID) -> WorkspaceItem? {
    items.first(id)
  }

  /// 新しい項目を置くフォルダ。フォルダを選んでいればその中、ファイルならその隣、何も選んでいなければ一番上（nil）
  public func folderForNewItem(selection: UUID?) -> UUID? {
    guard let selection, let selected = item(selection) else { return nil }
    return selected.isFolder ? selection : items.parent(of: selection) ?? nil
  }

  /// 同じフォルダの中でかぶらない名前。「新規ファイル.txt」「新規ファイル 2.txt」…
  public func uniqueName(_ name: String, in folder: UUID?) -> String {
    let siblings = (try? children(of: folder)) ?? []
    let ext = (name as NSString).pathExtension
    let stem = (name as NSString).deletingPathExtension
    var candidate = name
    var number = 2
    while siblings.contains(where: { $0.name.localizedCaseInsensitiveCompare(candidate) == .orderedSame }) {
      candidate = ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)"
      number += 1
    }
    return candidate
  }

  // MARK: - 変更

  public mutating func add(_ item: WorkspaceItem, to folder: UUID?) throws {
    var item = item
    item.name = try validatedName(item.name, in: folder, excluding: nil)
    if let folder {
      try modifyFolder(folder) { $0.append(item) }
    } else {
      items.append(item)
      items = items.sortedForDisplay()
    }
  }

  public mutating func rename(_ id: UUID, to name: String) throws {
    guard items.first(id) != nil else { throw WorkspaceError.notFound }
    let parent = items.parent(of: id) ?? nil
    let name = try validatedName(name, in: parent, excluding: id)
    if let parent {
      try modifyFolder(parent) { children in
        if let index = children.firstIndex(where: { $0.id == id }) { children[index].name = name }
      }
    } else if let index = items.firstIndex(where: { $0.id == id }) {
      items[index].name = name
      items = items.sortedForDisplay()
    }
  }

  /// 項目を別のフォルダ（nil なら一番上）へ移す。フォルダなら中身ごと移る。
  /// 移せないとき（自分の中へ入れる、同じ名前がある）は何も変えずにエラーにする
  public mutating func move(_ id: UUID, to folder: UUID?) throws {
    guard let item = item(id) else { throw WorkspaceError.notFound }
    if items.parent(of: id) == .some(folder) { return }
    if let folder, folder == id || item.children?.first(folder) != nil {
      throw WorkspaceError.cannotMoveIntoItself
    }
    // 取り除く前に確かめておく（途中で失敗して項目が消えるのを防ぐ）
    _ = try validatedName(item.name, in: folder, excluding: nil)
    remove(id)
    try add(item, to: folder)
  }

  /// 項目を取り除く。フォルダなら中身ごと消える
  @discardableResult
  public mutating func remove(_ id: UUID) -> WorkspaceItem? {
    items.remove(id)
  }

  public mutating func setText(_ text: String, for id: UUID) {
    items.modify(id) { item in
      if !item.isFolder && !item.isSheet && !item.isPDF { item.text = text }
    }
  }

  public mutating func setSheet(_ workbook: Workbook, for id: UUID) {
    items.modify(id) { item in
      if item.isSheet { item.sheet = workbook }
    }
  }

  // MARK: - 内部

  private func children(of folder: UUID?) throws -> [WorkspaceItem] {
    guard let folder else { return items }
    guard let item = item(folder) else { throw WorkspaceError.notFound }
    guard let children = item.children else { throw WorkspaceError.notAFolder }
    return children
  }

  private func validatedName(_ name: String, in folder: UUID?, excluding id: UUID?) throws -> String {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
      throw WorkspaceError.invalidName
    }
    let siblings = try children(of: folder)
    if siblings.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
      throw WorkspaceError.duplicateName(name)
    }
    return name
  }

  private mutating func modifyFolder(_ folder: UUID, _ body: (inout [WorkspaceItem]) -> Void) throws {
    var result: Result<Void, WorkspaceError> = .failure(.notFound)
    items.modify(folder) { item in
      guard var children = item.children else {
        result = .failure(.notAFolder)
        return
      }
      body(&children)
      item.children = children.sortedForDisplay()
      result = .success(())
    }
    try result.get()
  }
}

public struct WorkspaceItem: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var name: String
  /// フォルダなら中身（空でも nil ではない）、ファイルなら nil
  public var children: [WorkspaceItem]?
  /// ファイルの本文。フォルダと表では空
  public var text: String
  /// 表のファイルなら中身。テキストのファイルとフォルダでは nil。
  /// 種類は作ったときに決まり、名前（拡張子）を変えても変わらない
  public var sheet: Workbook?
  /// PDF の中身（そのままのバイト列）。PDF でなければ nil。見るだけで、金庫の中では書き換えない
  public var data: Data?

  public var isFolder: Bool { children != nil }
  public var isSheet: Bool { sheet != nil }
  public var isPDF: Bool { data != nil }

  public static func file(_ name: String, text: String = "") -> WorkspaceItem {
    WorkspaceItem(id: UUID(), name: name, children: nil, text: text)
  }

  public static func sheet(_ name: String, workbook: Workbook = Workbook()) -> WorkspaceItem {
    WorkspaceItem(id: UUID(), name: name, children: nil, text: "", sheet: workbook)
  }

  public static func pdf(_ name: String, data: Data) -> WorkspaceItem {
    WorkspaceItem(id: UUID(), name: name, children: nil, text: "", data: data)
  }

  public static func folder(_ name: String, children: [WorkspaceItem] = []) -> WorkspaceItem {
    WorkspaceItem(id: UUID(), name: name, children: children.sortedForDisplay(), text: "")
  }
}

public enum WorkspaceError: Error, Equatable, LocalizedError {
  case unsupportedVersion(Int)
  case invalidName
  case duplicateName(String)
  case notFound
  case notAFolder
  case cannotMoveIntoItself
  case invalidSheetName

  public var errorDescription: String? {
    switch self {
    case .unsupportedVersion(let v): "このアプリより新しい形式の金庫です（形式 \(v)）。アプリを更新してください。"
    case .invalidName: "その名前は使えません。空の名前や「/」を含む名前は付けられません。"
    case .duplicateName(let name): "「\(name)」はすでにあります。"
    case .notFound: "項目が見つかりません。"
    case .notAFolder: "フォルダではありません。"
    case .cannotMoveIntoItself: "フォルダを、そのフォルダ自身の中へは移動できません。"
    case .invalidSheetName: "そのシート名は使えません。31 文字以内で、[ ] : * ? / \\ は使えません。"
    }
  }
}

extension [WorkspaceItem] {
  /// フォルダを先に、その中は Finder と同じ並び（数字は数として比べる）
  fileprivate func sortedForDisplay() -> [WorkspaceItem] {
    sorted { a, b in
      if a.isFolder != b.isFolder { return a.isFolder }
      return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }
  }

  fileprivate func first(_ id: UUID) -> WorkspaceItem? {
    for item in self {
      if item.id == id { return item }
      if let found = item.children?.first(id) { return found }
    }
    return nil
  }

  /// 親フォルダの id。一番上にあれば .some(nil)、見つからなければ nil
  fileprivate func parent(of id: UUID, under folder: UUID? = nil) -> UUID?? {
    for item in self {
      if item.id == id { return .some(folder) }
      if let found = item.children?.parent(of: id, under: item.id) { return found }
    }
    return nil
  }

  fileprivate mutating func modify(_ id: UUID, _ body: (inout WorkspaceItem) -> Void) {
    for index in indices {
      if self[index].id == id {
        body(&self[index])
        return
      }
      if self[index].children != nil {
        self[index].children!.modify(id, body)
      }
    }
  }

  fileprivate mutating func remove(_ id: UUID) -> WorkspaceItem? {
    if let index = firstIndex(where: { $0.id == id }) { return remove(at: index) }
    for index in indices where self[index].children != nil {
      if let removed = self[index].children!.remove(id) { return removed }
    }
    return nil
  }
}
