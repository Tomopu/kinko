import Foundation

/// XMLParser（SAX: 先頭から順に要素の開始・終了を知らせる方式）を、クロージャで使えるようにする薄い包み。
/// 木を作らずに読むので、何十万セルのシートでもメモリは中身の分しか使わない
final class XMLScanner: NSObject, XMLParserDelegate {
  /// name は名前空間の接頭辞を外した名前（"x:c" も "c" も "c"）。path は親から根までの要素名（自分は含まない）
  typealias Start = (_ name: String, _ attributes: [String: String], _ path: [String]) throws -> Void
  typealias End = (_ name: String, _ text: String, _ path: [String]) throws -> Void

  private let onStart: Start
  private let onEnd: End
  private var path: [String] = []
  private var text = ""
  private var failure: (any Error)?

  private init(onStart: @escaping Start, onEnd: @escaping End) {
    self.onStart = onStart
    self.onEnd = onEnd
  }

  /// part はエラーで示す部品の名前
  static func scan(_ data: Data, part: String, start: @escaping Start = { _, _, _ in }, end: @escaping End = { _, _, _ in }) throws {
    // DTD（<!DOCTYPE ...>）は Excel の XML には現れない。DTD の中で実体を定義すると、
    // 外部のファイルを読ませたり（XXE）、入れ子の展開で何 GB にも膨らませたり（Billion Laughs）できるので、
    // DTD があるだけで読むのをやめる
    guard data.range(of: Data("<!DOCTYPE".utf8)) == nil else { throw SpreadsheetFileError.invalidPart(part) }
    let scanner = XMLScanner(onStart: start, onEnd: end)
    let parser = XMLParser(data: data)
    // 外部実体を解決しない（既定でも false だが、XXE を防ぐ要の設定なので明示しておく）
    parser.shouldResolveExternalEntities = false
    parser.shouldProcessNamespaces = false
    parser.delegate = scanner
    let succeeded = parser.parse()
    if let failure = scanner.failure { throw failure }
    guard succeeded else { throw SpreadsheetFileError.invalidPart(part) }
  }

  private static func localName(_ name: String) -> String {
    guard let colon = name.lastIndex(of: ":") else { return name }
    return String(name[name.index(after: colon)...])
  }

  private func fail(_ parser: XMLParser, _ error: any Error) {
    if failure == nil { failure = error }
    parser.abortParsing()
  }

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    guard failure == nil else { return }
    let name = Self.localName(elementName)
    var attributes: [String: String] = [:]
    for (key, value) in attributeDict where !key.hasPrefix("xmlns") {
      attributes[Self.localName(key)] = value
    }
    do { try onStart(name, attributes, path) } catch { fail(parser, error) }
    path.append(name)
    text = ""
  }

  func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
    guard failure == nil else { return }
    if !path.isEmpty { path.removeLast() }
    do { try onEnd(Self.localName(elementName), text, path) } catch { fail(parser, error) }
    text = ""
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    text += string
  }

  func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
    text += String(decoding: CDATABlock, as: UTF8.self)
  }

  // 実体の定義が来たら止める（上の DOCTYPE の検査をすり抜けた場合の二重の守り。UTF-16 の XML など）
  func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
    fail(parser, SpreadsheetFileError.invalidPart("DTD"))
  }

  func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) {
    fail(parser, SpreadsheetFileError.invalidPart("DTD"))
  }

  func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
    fail(parser, SpreadsheetFileError.invalidPart("DTD"))
    return nil
  }
}
