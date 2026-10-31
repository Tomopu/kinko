import AppKit
import KinkoCore
import LocalAuthentication
import Observation
import UniformTypeIdentifiers

/// 金庫ファイル 1 つを開いて編集する間の状態。平文はこのオブジェクトのメモリ上にだけ置き、ディスクには暗号文しか書かない
@MainActor @Observable
final class VaultSession {
  enum Phase: Equatable {
    case start
    case creating(URL)
    case unlocking(URL)
    /// 復旧コードで開き、新しいパスワードを決め直す
    case recovering(URL)
    case editing(URL)
  }

  /// 開こうとしている金庫について、開く画面に出すこと
  struct UnlockOptions: Equatable {
    var protection: UnlockedVault.Protection?
    /// この Mac 専用の金庫で、この Mac にその鍵がある
    var hasDeviceKey = false
    var canUseTouchID = false
  }

  /// 控えてもらう復旧コード。設定画面から作ったときは、設定画面の上に出す
  struct PendingRecoveryCode: Equatable {
    var code: RecoveryCode
    var fromSettings: Bool
  }

  static let fileType = UTType(filenameExtension: "kinko", conformingTo: .data) ?? .data
  /// Touch ID だけで開ける期間。過ぎたら一度パスワードで開いてもらう（パスワードを忘れないように）
  static let touchIDValidity: TimeInterval = 7 * 24 * 60 * 60

  private(set) var phase: Phase = .start
  private(set) var workspace = Workspace()
  var selection: WorkspaceItem.ID?
  private(set) var isDirty = false
  private(set) var isBusy = false
  var errorMessage: String?
  /// 最初の画面に出す知らせ（パスワードを間違え続けて金庫を消したときなど）
  private(set) var notice: String?
  private(set) var unlockOptions = UnlockOptions()
  private(set) var pendingRecoveryCode: PendingRecoveryCode?

  /// パスワードの変更と、この Mac 専用への切り替えの結果（設定画面に出す）
  var keyChangeError: String?
  private(set) var keyChangeMessage: String?

  /// パスワードを何回続けて間違えたら金庫のファイルを消すか。nil なら消さない
  var eraseLimit: Int? {
    didSet { defaults.set(eraseLimit ?? 0, forKey: Self.eraseLimitKey) }
  }
  /// 開こうとしている金庫を、あと何回間違えると消すか（消さない設定か、まだ間違えていなければ nil）
  private(set) var remainingBeforeErase: Int?

  private var vault: UnlockedVault?
  private let defaults: UserDefaults
  let deviceKeys: DeviceKeyStore
  private static let eraseLimitKey = "eraseAfterFailedUnlocks"
  private static let attemptsKey = "unlockAttempts"
  private static let passwordUnlockedKey = "passwordUnlockedAt"

  init(defaults: UserDefaults = .standard, deviceKeys: DeviceKeyStore = .standard) {
    self.defaults = defaults
    self.deviceKeys = deviceKeys
    let limit = defaults.integer(forKey: Self.eraseLimitKey)
    eraseLimit = limit > 0 ? limit : nil
  }

  /// 開いている金庫の守り方（開いていなければ nil）
  var protection: UnlockedVault.Protection? { vault?.protection }
  /// 開いている金庫を Touch ID で開けるか（鍵のファイルは見張れないので、変えたときに読み直す）
  private(set) var isTouchIDEnabled = false

  private func refreshTouchIDState() {
    isTouchIDEnabled = vault.map { deviceKeys.hasTouchID(for: $0.identifier) } ?? false
  }

  // MARK: - 作る・開く

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
    remainingBeforeErase = nil
    unlockOptions = UnlockOptions()
    if let file = try? Data(contentsOf: url), let id = try? UnlockedVault.identifier(ofFile: file) {
      let protection = try? UnlockedVault.protection(ofFile: file)
      let unlockedAt = (defaults.dictionary(forKey: Self.passwordUnlockedKey)?[id] as? Date) ?? .distantPast
      unlockOptions = UnlockOptions(
        protection: protection,
        hasDeviceKey: protection == .deviceBound && deviceKeys.deviceKey(for: id) != nil,
        canUseTouchID: deviceKeys.hasTouchID(for: id) && DeviceKeyStore.isTouchIDAvailable
          && Date().timeIntervalSince(unlockedAt) < Self.touchIDValidity)
      if attempts.failures(of: id) > 0 { remainingBeforeErase = attempts.remaining(of: id, limit: eraseLimit) }
    }
    phase = .unlocking(url)
  }

  func beginRecovery(_ url: URL) {
    errorMessage = nil
    phase = .recovering(url)
  }

  /// 新しい金庫を作る。bindToThisMac なら、この Mac の Secure Enclave の鍵と組み合わせ、復旧コードを出す
  func create(at url: URL, password: String, confirmation: String, bindToThisMac: Bool) async {
    guard validateNewPassword(password, confirmation) else { return }
    await run {
      let deviceKey = bindToThisMac ? try deviceKeys.newDeviceKey() : nil
      // Argon2id は 0.5 秒ほどかかるので、画面を止めないように別スレッドで回す
      let (vault, code): (UnlockedVault, RecoveryCode?) = try await Task.detached {
        guard let deviceKey else { return (try UnlockedVault.create(password: password), nil) }
        let created = try UnlockedVault.create(password: password, deviceKey: deviceKey)
        return (created.vault, created.recoveryCode)
      }.value
      let workspace = Workspace(items: [.file("メモ.md")])
      if let deviceKey { try deviceKeys.save(deviceKey, for: vault.identifier) }
      do {
        try vault.seal(workspace.encoded()).write(to: url, options: .atomic)
      } catch {
        deviceKeys.removeAll(for: vault.identifier)
        throw error
      }
      recordPasswordUnlock(of: vault.identifier)
      enterEditing(url: url, vault: vault, workspace: workspace)
      if let code { pendingRecoveryCode = PendingRecoveryCode(code: code, fromSettings: false) }
    }
  }

  /// 開く。パスワードの間違いを数え、決めた回数に達したら金庫を消す
  func unlock(at url: URL, password: String) async {
    isBusy = true
    defer { isBusy = false }
    do {
      let file = try Data(contentsOf: url)
      let id = try UnlockedVault.identifier(ofFile: file)
      let deviceKey = deviceKeys.deviceKey(for: id)
      do {
        let (vault, plaintext) = try await Task.detached {
          try UnlockedVault.open(file, password: password, deviceKey: deviceKey)
        }.value
        updateAttempts { $0.recordSuccess(of: id) }
        recordPasswordUnlock(of: id)
        enterEditing(url: url, vault: vault, workspace: try Workspace.decode(plaintext))
      } catch VaultError.authenticationFailed {
        switch updateAttempts({ $0.recordFailure(of: id, limit: eraseLimit) }) {
        case .retry(let remaining):
          remainingBeforeErase = remaining
          errorMessage = VaultError.authenticationFailed.localizedDescription
        case .erase:
          erase(url, vault: id)
        }
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// Touch ID で開く。指紋の確認は macOS が出す
  func unlockWithTouchID(at url: URL) async {
    isBusy = true
    defer { isBusy = false }
    do {
      let file = try Data(contentsOf: url)
      let id = try UnlockedVault.identifier(ofFile: file)
      let deviceKeys = deviceKeys
      let reason = "「\(url.deletingPathExtension().lastPathComponent)」を開く"
      let (vault, plaintext) = try await Task.detached {
        try deviceKeys.openWithTouchID(file, vault: id, reason: reason)
      }.value
      updateAttempts { $0.recordSuccess(of: id) }
      enterEditing(url: url, vault: vault, workspace: try Workspace.decode(plaintext))
    } catch let error as LAError where error.code == .userCancel || error.code == .appCancel || error.code == .systemCancel {
      // 取り消しただけなら、パスワードで開いてもらう
    } catch {
      errorMessage = "Touch ID で開けませんでした。パスワードで開いてください。"
    }
  }

  /// 復旧コードで開き、新しいパスワードとこの Mac の鍵で作り直す。新しい復旧コードを出す
  func recover(at url: URL, code text: String, password: String, confirmation: String) async {
    guard let code = RecoveryCode(text) else {
      errorMessage = "復旧コードは、英数字 24 文字です（「-」や空白はなくてもかまいません）。"
      return
    }
    guard validateNewPassword(password, confirmation) else { return }
    await run {
      let file = try Data(contentsOf: url)
      let (opened, plaintext) = try await Task.detached { try UnlockedVault.open(file, recoveryCode: code) }.value
      let workspace = try Workspace.decode(plaintext)
      let (vault, newCode) = try await rekey(opened, password: password, bindToThisMac: true, url: url, workspace: workspace)
      recordPasswordUnlock(of: vault.identifier)
      enterEditing(url: url, vault: vault, workspace: workspace)
      if let newCode { pendingRecoveryCode = PendingRecoveryCode(code: newCode, fromSettings: false) }
    }
  }

  func acknowledgeRecoveryCode() {
    pendingRecoveryCode = nil
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

  // MARK: - 失敗回数と消去

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

  /// パスワードを間違え続けた金庫を消して、最初の画面に戻る。
  /// この Mac の鍵を先に消す。この Mac 専用の金庫なら、これでどこかに残ったコピーも、パスワードでは二度と開けなくなる。
  /// ファイルはゴミ箱には入れない（ゴミ箱から戻して試し続けられるので）
  private func erase(_ url: URL, vault id: String) {
    deviceKeys.removeAll(for: id)
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

  // MARK: - 鍵の作り直し（パスワードの変更・この Mac 専用への切り替え・Touch ID）

  /// パスワードを変えて、金庫全体を新しい鍵で暗号化し直して保存する（編集中の内容も一緒に保存される）。
  /// この Mac 専用の金庫なら、復旧コードも新しくなる
  func changePassword(current: String, new: String, confirmation: String) async {
    guard let vault, validateNewPassword(new, confirmation, report: { self.keyChangeError = $0 }) else { return }
    await changeKeys(password: current, successMessage: "パスワードを変更しました。") {
      try await self.rekey(vault, password: new, bindToThisMac: vault.protection == .deviceBound)
    }
  }

  /// この Mac 専用にする（bind）か、どの Mac でも開ける金庫に戻す。パスワードは変えない
  func setDeviceBound(_ bind: Bool, password: String) async {
    guard let vault else { return }
    await changeKeys(
      password: password,
      successMessage: bind ? "この Mac 専用にしました。" : "どの Mac でも開ける金庫に戻しました。"
    ) {
      try await self.rekey(vault, password: password, bindToThisMac: bind)
    }
  }

  /// Touch ID で開けるようにする・やめる。オンにするときは、指紋で本人か確かめる
  func setTouchID(_ enabled: Bool) async {
    guard let vault else { return }
    keyChangeError = nil
    keyChangeMessage = nil
    defer { refreshTouchIDState() }
    guard enabled else {
      deviceKeys.removeTouchID(for: vault.identifier)
      return
    }
    do {
      let context = LAContext()
      try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Touch ID で金庫を開けるようにする")
      try deviceKeys.enableTouchID(for: vault)
      keyChangeMessage = "Touch ID で開けるようにしました。"
    } catch let error as LAError where error.code == .userCancel || error.code == .appCancel || error.code == .systemCancel {
      // 取り消したときは何もしない
    } catch {
      keyChangeError = "Touch ID をオンにできませんでした。\(error.localizedDescription)"
    }
  }

  /// 今のパスワードを確かめてから鍵を作り直す（開いたまま席を離れた間に、他人に乗っ取られるのを防ぐ）
  private func changeKeys(
    password: String, successMessage: String, _ change: () async throws -> (UnlockedVault, RecoveryCode?)
  ) async {
    guard case .editing = phase, let vault else { return }
    keyChangeError = nil
    keyChangeMessage = nil
    isBusy = true
    defer { isBusy = false }
    let deviceKey = deviceKeys.deviceKey(for: vault.identifier)
    let isCorrect = await Task.detached { vault.verifies(password: password, deviceKey: deviceKey) }.value
    guard isCorrect else {
      keyChangeError = "今のパスワードが違います。"
      return
    }
    do {
      let (changed, code) = try await change()
      self.vault = changed
      refreshTouchIDState()
      isDirty = false
      recordPasswordUnlock(of: changed.identifier)
      keyChangeMessage = successMessage
      if let code { pendingRecoveryCode = PendingRecoveryCode(code: code, fromSettings: true) }
    } catch {
      keyChangeError = error.localizedDescription
    }
  }

  /// 新しい鍵で作り直して保存し、この Mac の鍵を付け替える。古い鍵は、保存できてから消す。
  /// Touch ID がオンなら、新しいデータ鍵で包み直す（指紋は要らない）
  private func rekey(
    _ vault: UnlockedVault, password: String, bindToThisMac: Bool, url: URL? = nil, workspace: Workspace? = nil
  ) async throws -> (UnlockedVault, RecoveryCode?) {
    guard let url = url ?? phase.url else { throw CocoaError(.fileNoSuchFile) }
    let deviceKey = bindToThisMac ? try deviceKeys.newDeviceKey() : nil
    let (changed, code) = try await Task.detached { try vault.rekeyed(password: password, deviceKey: deviceKey) }.value
    if let deviceKey { try deviceKeys.save(deviceKey, for: changed.identifier) }
    do {
      try changed.seal((workspace ?? self.workspace).encoded()).write(to: url, options: .atomic)
    } catch {
      deviceKeys.removeAll(for: changed.identifier)
      throw error
    }
    let hadTouchID = deviceKeys.hasTouchID(for: vault.identifier)
    deviceKeys.removeAll(for: vault.identifier)
    if hadTouchID { try? deviceKeys.enableTouchID(for: changed) }
    return (changed, code)
  }

  private func recordPasswordUnlock(of id: String) {
    var dates = defaults.dictionary(forKey: Self.passwordUnlockedKey) ?? [:]
    dates[id] = Date()
    defaults.set(dates, forKey: Self.passwordUnlockedKey)
  }

  private func validateNewPassword(
    _ password: String, _ confirmation: String, report: ((String) -> Void)? = nil
  ) -> Bool {
    let report = report ?? { self.errorMessage = $0 }
    do {
      try PasswordPolicy.validate(password)
    } catch {
      report(error.localizedDescription)
      return false
    }
    guard password == confirmation else {
      report("確認用のパスワードが一致しません。")
      return false
    }
    return true
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
    isTouchIDEnabled = false
    keyChangeError = nil
    keyChangeMessage = nil
    pendingRecoveryCode = nil
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

  /// 復旧をやめて、開く画面に戻る
  func cancelRecovery() {
    guard case .recovering(let url) = phase else { return }
    beginUnlocking(url)
  }

  private func enterEditing(url: URL, vault: UnlockedVault, workspace: Workspace) {
    self.vault = vault
    self.workspace = workspace
    selection = workspace.items.first { !$0.isFolder }?.id
    isDirty = false
    errorMessage = nil
    phase = .editing(url)
    refreshTouchIDState()
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

extension VaultSession.Phase {
  /// 開いている・開こうとしている金庫のファイル
  var url: URL? {
    switch self {
    case .start: nil
    case .creating(let url), .unlocking(let url), .recovering(let url), .editing(let url): url
    }
  }
}
