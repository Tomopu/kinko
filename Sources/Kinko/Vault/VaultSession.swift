import AppKit
import KinkoCore
import Observation
import UniformTypeIdentifiers

/// 金庫ファイル 1 つを開いて編集する間の状態。平文はこのオブジェクトのメモリ上にだけ置き、ディスクには暗号文しか書かない
@MainActor @Observable
final class VaultSession {
  enum Phase: Equatable {
    case start
    case creating(URL)
    case unlocking(URL)
    case editing(URL)
  }

  static let fileType = UTType(filenameExtension: "kinko", conformingTo: .data) ?? .data

  private(set) var phase: Phase = .start
  private(set) var workspace = Workspace()
  var selection: WorkspaceItem.ID?
  private(set) var isDirty = false
  private(set) var isBusy = false
  var errorMessage: String?
  /// 最初の画面に出す知らせ（パスワードを間違え続けて金庫を消したときなど）
  private(set) var notice: String?

  /// パスワードの変更の結果（設定画面に出す）
  var passwordChangeError: String?
  private(set) var passwordChanged = false

  /// パスワードを何回続けて間違えたら金庫のファイルを消すか。nil なら消さない
  var eraseLimit: Int? {
    didSet { defaults.set(eraseLimit ?? 0, forKey: Self.eraseLimitKey) }
  }
  /// 開こうとしている金庫を、あと何回間違えると消すか（消さない設定か、まだ間違えていなければ nil）
  private(set) var remainingBeforeErase: Int?

  private var vault: UnlockedVault?
  private let defaults: UserDefaults
  private static let eraseLimitKey = "eraseAfterFailedUnlocks"
  private static let attemptsKey = "unlockAttempts"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let limit = defaults.integer(forKey: Self.eraseLimitKey)
    eraseLimit = limit > 0 ? limit : nil
  }

  func chooseNewFile() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [Self.fileType]
    panel.nameFieldStringValue = "金庫.kinko"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    errorMessage = nil
    notice = nil
    phase = .creating(url)
  }

  func chooseExistingFile() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [Self.fileType]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    beginUnlocking(url)
  }

  func beginUnlocking(_ url: URL) {
    errorMessage = nil
    notice = nil
    remainingBeforeErase = (try? Data(contentsOf: url)).flatMap { file in
      guard let id = try? UnlockedVault.identifier(ofFile: file), attempts.failures(of: id) > 0 else { return nil }
      return attempts.remaining(of: id, limit: eraseLimit)
    }
    phase = .unlocking(url)
  }

  func create(at url: URL, password: String, confirmation: String) async {
    do {
      try PasswordPolicy.validate(password)
    } catch {
      errorMessage = error.localizedDescription
      return
    }
    guard password == confirmation else {
      errorMessage = "確認用のパスワードが一致しません。"
      return
    }
    await run {
      // Argon2id は 0.5 秒ほどかかるので、画面を止めないように別スレッドで回す
      let vault = try await Task.detached { try UnlockedVault.create(password: password) }.value
      let workspace = Workspace(items: [.file("メモ.md")])
      try vault.seal(workspace.encoded()).write(to: url, options: .atomic)
      self.enterEditing(url: url, vault: vault, workspace: workspace)
    }
  }

  /// 開く。パスワードの間違いを数え、決めた回数に達したら金庫のファイルを消す
  func unlock(at url: URL, password: String) async {
    isBusy = true
    defer { isBusy = false }
    do {
      let file = try Data(contentsOf: url)
      let id = try UnlockedVault.identifier(ofFile: file)
      do {
        let (vault, plaintext) = try await Task.detached { try UnlockedVault.open(file, password: password) }.value
        updateAttempts { $0.recordSuccess(of: id) }
        enterEditing(url: url, vault: vault, workspace: try Workspace.decode(plaintext))
      } catch VaultError.authenticationFailed {
        switch updateAttempts({ $0.recordFailure(of: id, limit: eraseLimit) }) {
        case .retry(let remaining):
          remainingBeforeErase = remaining
          errorMessage = VaultError.authenticationFailed.localizedDescription
        case .erase:
          erase(url)
        }
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// 続けて間違えた回数の記録。金庫ごとに、この Mac の設定に置く
  private var attempts: UnlockAttempts {
    get { defaults.data(forKey: Self.attemptsKey).flatMap { try? JSONDecoder().decode(UnlockAttempts.self, from: $0) } ?? UnlockAttempts() }
    set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.attemptsKey) }
  }

  private func updateAttempts<T>(_ change: (inout UnlockAttempts) -> T) -> T {
    var attempts = attempts
    defer { self.attempts = attempts }
    return change(&attempts)
  }

  /// パスワードを間違え続けた金庫のファイルを消して、最初の画面に戻る。
  /// ゴミ箱には入れない（ゴミ箱から戻して試し続けられるので）
  private func erase(_ url: URL) {
    do {
      try FileManager.default.removeItem(at: url)
      notice = "パスワードを \(eraseLimit ?? 0) 回続けて間違えたため、「\(url.lastPathComponent)」を削除しました。"
      errorMessage = nil
      remainingBeforeErase = nil
      phase = .start
    } catch {
      errorMessage = "パスワードを続けて間違えたので削除しようとしましたが、できませんでした。\(error.localizedDescription)"
    }
  }

  func save() {
    guard case .editing(let url) = phase, let vault else { return }
    do {
      // .atomic は一時ファイルに書いてから置き換える。一時ファイルの中身も暗号文なので平文は残らない
      try vault.seal(workspace.encoded()).write(to: url, options: .atomic)
      isDirty = false
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  // MARK: - パスワードの変更

  /// パスワードを変えて、金庫全体を新しい鍵で暗号化し直して保存する（編集中の内容も一緒に保存される）
  func changePassword(current: String, new: String, confirmation: String) async {
    guard case .editing(let url) = phase, let vault else { return }
    passwordChanged = false
    do {
      try PasswordPolicy.validate(new)
    } catch {
      passwordChangeError = error.localizedDescription
      return
    }
    guard new == confirmation else {
      passwordChangeError = "確認用のパスワードが一致しません。"
      return
    }
    isBusy = true
    defer { isBusy = false }
    do {
      // 開いたまま席を離れた間に、他人がパスワードを変えて乗っ取るのを防ぐ
      let isCorrect = await Task.detached { vault.verifies(password: current) }.value
      guard isCorrect else {
        passwordChangeError = "今のパスワードが違います。"
        return
      }
      let changed = try await Task.detached { try vault.changingPassword(to: new) }.value
      try changed.seal(workspace.encoded()).write(to: url, options: .atomic)
      self.vault = changed
      isDirty = false
      passwordChangeError = nil
      passwordChanged = true
    } catch {
      passwordChangeError = error.localizedDescription
    }
  }

  // MARK: - ワークスペースの編集

  func text(of id: WorkspaceItem.ID) -> String {
    workspace.item(id)?.text ?? ""
  }

  func setText(_ text: String, of id: WorkspaceItem.ID) {
    guard workspace.item(id)?.text != text else { return }
    workspace.setText(text, for: id)
    isDirty = true
  }

  func workbook(of id: WorkspaceItem.ID) -> Workbook {
    workspace.item(id)?.sheet ?? Workbook()
  }

  func setWorkbook(_ workbook: Workbook, of id: WorkspaceItem.ID) {
    guard let item = workspace.item(id), item.isSheet, item.sheet != workbook else { return }
    workspace.setSheet(workbook, for: id)
    isDirty = true
  }

  /// 選んでいる場所に置いたときの、かぶらない名前
  func suggestedName(_ name: String) -> String {
    workspace.uniqueName(name, in: workspace.folderForNewItem(selection: selection))
  }

  func addItem(_ item: WorkspaceItem) {
    edit {
      try $0.add(item, to: $0.folderForNewItem(selection: selection))
      selection = item.id
    }
  }

  func rename(_ id: WorkspaceItem.ID, to name: String) {
    edit { try $0.rename(id, to: name) }
  }

  /// ドラッグ＆ドロップでの移動。移せなかったら false
  @discardableResult
  func move(_ id: WorkspaceItem.ID, to folder: WorkspaceItem.ID?) -> Bool {
    edit { try $0.move(id, to: folder) }
  }

  func remove(_ id: WorkspaceItem.ID) {
    edit { _ = $0.remove(id) }
    if let selection, workspace.item(selection) == nil { self.selection = nil }
  }

  @discardableResult
  private func edit(_ change: (inout Workspace) throws -> Void) -> Bool {
    let before = workspace
    do {
      try change(&workspace)
      if workspace != before { isDirty = true }
      errorMessage = nil
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }

  // MARK: - 読み込みと書き出し

  /// 金庫の外のファイルやフォルダを読み込む。元のファイルは消さない
  func importFiles() {
    guard case .editing = phase else { return }
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = true
    panel.prompt = "読み込む"
    panel.message = "テキスト・Markdown・CSV・Excel（.xlsx）を読み込めます。元のファイルは暗号化されないまま残るので、不要なら自分で削除してください。"
    guard panel.runModal() == .OK else { return }
    let urls = panel.urls
    Task { await importItems(from: urls) }
  }

  func importItems(from urls: [URL]) async {
    isBusy = true
    defer { isBusy = false }
    // 大きな .xlsx の解析で画面が止まらないよう、別スレッドで読む
    let results = await Task.detached {
      urls.map { url in Result { try FileTransfer.importItem(at: url) } }
    }.value
    let folder = workspace.folderForNewItem(selection: selection)
    var failures: [String] = []
    var lastAdded: WorkspaceItem.ID?
    for result in results {
      switch result {
      case .success(var item):
        item.name = workspace.uniqueName(item.name, in: folder)
        if edit({ try $0.add(item, to: folder) }) { lastAdded = item.id }
      case .failure(let error):
        failures.append(error.localizedDescription)
      }
    }
    if let lastAdded { selection = lastAdded }
    if let first = failures.first {
      errorMessage = failures.count == 1 ? first : "\(first)（ほか \(failures.count - 1) 件も読み込めませんでした）"
    }
  }

  /// 選んでいる項目（何も選んでいなければ金庫全体）を、暗号化せずに書き出す
  func exportSelection() {
    guard case .editing(let url) = phase else { return }
    let item =
      selection.flatMap { workspace.item($0) }
      ?? .folder(url.deletingPathExtension().lastPathComponent, children: workspace.items)
    let warning = "書き出したファイルは暗号化されません。ほかのアプリやバックアップ、Spotlight からも読めるようになります。"
    do {
      if item.isFolder {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "ここに書き出す"
        panel.message = "「\(item.name)」を選んだ場所にフォルダごと書き出します。" + warning
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        var target = directory.appendingPathComponent(item.name)
        var number = 2
        while FileManager.default.fileExists(atPath: target.path) {
          target = directory.appendingPathComponent("\(item.name) \(number)")
          number += 1
        }
        try FileTransfer.export(item, to: target)
      } else {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = FileTransfer.exportName(for: item)
        panel.canCreateDirectories = true
        panel.message = item.isSheet
          ? warning + "名前を .csv にすると、最初のシートだけを CSV で書き出します。" : warning
        if item.isSheet {
          panel.allowedContentTypes = [UTType(filenameExtension: "xlsx") ?? .data, .commaSeparatedText, .tabSeparatedText]
        }
        guard panel.runModal() == .OK, let target = panel.url else { return }
        // 保存パネルで上書きを確認済みなので、ここでは上書きする
        try FileTransfer.exportData(for: item, as: target.lastPathComponent).write(to: target, options: .atomic)
      }
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  // MARK: - ロック

  /// 鍵と平文を手放して最初の画面に戻る。保存していない変更は捨てる
  func lock() {
    vault = nil
    passwordChangeError = nil
    passwordChanged = false
    workspace = Workspace()
    selection = nil
    isDirty = false
    errorMessage = nil
    phase = .start
  }

  func cancel() {
    errorMessage = nil
    remainingBeforeErase = nil
    phase = .start
  }

  private func enterEditing(url: URL, vault: UnlockedVault, workspace: Workspace) {
    self.vault = vault
    self.workspace = workspace
    selection = workspace.items.first { !$0.isFolder }?.id
    isDirty = false
    errorMessage = nil
    phase = .editing(url)
  }

  #if DEBUG
  /// 開発用の画面書き出し（Snapshot.swift）で、好きな状態を作る
  func preview(phase: Phase, workspace: Workspace = Workspace(), selection: WorkspaceItem.ID? = nil, isDirty: Bool = false) {
    self.phase = phase
    self.workspace = workspace
    self.selection = selection
    self.isDirty = isDirty
  }
  #endif

  private func run(_ work: () async throws -> Void) async {
    isBusy = true
    defer { isBusy = false }
    do {
      try await work()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
