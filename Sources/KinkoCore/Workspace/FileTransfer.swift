import Foundation

/// 金庫の外のファイルとのやりとり。読み込みは平文のファイルを金庫の中へ写し、書き出しは金庫の中身を平文で外に書く。
/// どちらも元（読み込みなら元のファイル、書き出しなら書いたファイル）は暗号化されないまま残る
public enum FileTransfer {
  /// 1 つのファイルの大きさの上限。金庫は保存のたびに全体を暗号化し直すので、大きなファイルは向かない
  public static let maxFileSize = 50 * 1024 * 1024
  /// フォルダを読み込むときの、ファイルとフォルダの数と深さの上限（ホームフォルダを丸ごと選んでしまったときなどに止める）
  public static let maxItems = 2_000
  public static let maxDepth = 16

  public static let sheetExtensions: Set<String> = ["xlsx", "csv", "tsv"]

  // MARK: - 読み込み

  /// ファイルかフォルダを読み込んで、金庫の項目にする
  public static func importItem(at url: URL) throws -> WorkspaceItem {
    var count = 0
    return try importItem(at: url, depth: 0, count: &count)
  }

  private static func importItem(at url: URL, depth: Int, count: inout Int) throws -> WorkspaceItem {
    count += 1
    guard count <= maxItems, depth <= maxDepth else { throw FileTransferError.tooManyItems }
    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
    // シンボリックリンクはたどらない（フォルダの外や自分自身を指して、思わぬものを取り込むのを防ぐ）
    if values.isSymbolicLink == true { throw FileTransferError.unsupported(url.lastPathComponent) }
    if values.isDirectory == true {
      let contents = try FileManager.default.contentsOfDirectory(
        at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles])
      var children: [WorkspaceItem] = []
      for child in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        if (try? child.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { continue }
        children.append(try importItem(at: child, depth: depth + 1, count: &count))
      }
      return .folder(url.lastPathComponent, children: children)
    }
    guard (values.fileSize ?? 0) <= maxFileSize else { throw FileTransferError.tooLarge(url.lastPathComponent) }
    return try importFile(named: url.lastPathComponent, data: Data(contentsOf: url))
  }

  /// ファイルの中身から項目を作る。表（.xlsx .csv .tsv）は表に、PDF は PDF に、それ以外はテキストとして読む
  public static func importFile(named name: String, data: Data) throws -> WorkspaceItem {
    guard data.count <= maxFileSize else { throw FileTransferError.tooLarge(name) }
    do {
      switch (name as NSString).pathExtension.lowercased() {
      // .xlsm のマクロは取り込まない（値と数式だけを読む）。古い .xls は XLSX.read が分かりやすいエラーにする
      case "xlsx", "xlsm", "xls":
        return .sheet(name, workbook: try XLSX.read(data))
      case "csv":
        return .sheet(name, workbook: Workbook(sheets: [try CSV.read(data, name: sheetName(for: name))]))
      case "tsv":
        return .sheet(name, workbook: Workbook(sheets: [try CSV.read(data, name: sheetName(for: name), separator: "\t")]))
      case "pdf":
        // PDF は先頭 1024 バイトの中に "%PDF-" がある（その前にごみがあってもよいことになっている）
        guard data.prefix(1024).range(of: Data("%PDF-".utf8)) != nil else { throw FileTransferError.notPDF(name) }
        return .pdf(name, data: data)
      default:
        return .file(name, text: try text(from: data, name: name))
      }
    } catch let error as FileTransferError {
      throw error
    } catch {
      throw FileTransferError.unreadable(name, error.localizedDescription)
    }
  }

  /// CSV のシート名はファイル名から付ける（Excel と同じ）。Excel のシート名に使えない文字は除く
  private static func sheetName(for fileName: String) -> String {
    let stem = (fileName as NSString).deletingPathExtension.filter { !"[]:*?/\\".contains($0) }
    return stem.isEmpty ? "Sheet1" : String(stem.prefix(31))
  }

  /// テキストとして読む。UTF-8（BOM あり・なし）、BOM 付きの UTF-16、それ以外は CP932（Windows の Shift_JIS）。
  /// NUL を含むものは画像や PDF などのバイナリとみなして断る（テキストとして取り込むと中身が壊れる）
  static func text(from data: Data, name: String) throws -> String {
    if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
      if let text = String(data: data, encoding: .utf16) { return text }
    }
    if data.contains(0) { throw FileTransferError.binary(name) }
    var bytes = data
    if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
    if let text = String(data: bytes, encoding: .utf8) { return text }
    let cp932 = String.Encoding(
      rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))
    if let text = String(data: data, encoding: cp932) { return text }
    throw FileTransferError.binary(name)
  }

  // MARK: - 書き出し

  /// 書き出すときの名前。拡張子のない表には .xlsx を付ける
  public static func exportName(for item: WorkspaceItem) -> String {
    guard item.isSheet, !sheetExtensions.contains((item.name as NSString).pathExtension.lowercased()) else { return item.name }
    return item.name + ".xlsx"
  }

  /// ファイル 1 つ分の中身。表は名前（拡張子）に合わせて .xlsx か CSV（最初のシートだけ）にする
  public static func exportData(for item: WorkspaceItem, as name: String? = nil) throws -> Data {
    if let data = item.data { return data }
    guard let workbook = item.sheet else { return Data(item.text.utf8) }
    let calculator = Calculator(workbook: workbook)
    switch ((name ?? exportName(for: item)) as NSString).pathExtension.lowercased() {
    case "csv":
      return CSV.write(workbook.sheets[0]) { calculator.value(sheet: 0, at: $0) }
    case "tsv":
      return CSV.write(workbook.sheets[0], values: { calculator.value(sheet: 0, at: $0) }, separator: "\t")
    default:
      return try XLSX.write(workbook) { calculator.value(sheet: $0, at: $1) }
    }
  }

  /// 項目を url に書き出す。フォルダなら中身ごと。すでにあるファイルは上書きしない
  public static func export(_ item: WorkspaceItem, to url: URL) throws {
    if let children = item.children {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
      for child in children {
        try export(child, to: url.appendingPathComponent(exportName(for: child)))
      }
    } else {
      try exportData(for: item, as: url.lastPathComponent).write(to: url, options: .withoutOverwriting)
    }
  }
}

public enum FileTransferError: Error, LocalizedError, Equatable {
  case tooLarge(String)
  case tooManyItems
  case binary(String)
  case unsupported(String)
  case unreadable(String, String)
  case notPDF(String)

  public var errorDescription: String? {
    switch self {
    case .tooLarge(let name): "「\(name)」は大きすぎます（\(FileTransfer.maxFileSize / 1024 / 1024) MB まで）。"
    case .tooManyItems: "ファイルが多すぎるか、フォルダが深すぎます（\(FileTransfer.maxItems) 個・\(FileTransfer.maxDepth) 階層まで）。"
    case .binary(let name): "「\(name)」はテキストではないので読み込めません。読み込めるのはテキスト・Markdown・CSV・Excel（.xlsx）・PDF です。"
    case .unsupported(let name): "「\(name)」は読み込めません（シンボリックリンクは読み込みません）。"
    case .unreadable(let name, let reason): "「\(name)」を読み込めません。\(reason)"
    case .notPDF(let name): "「\(name)」は PDF として読めません。ファイルが壊れているか、拡張子が違います。"
    }
  }
}
