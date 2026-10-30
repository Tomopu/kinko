import CoreTransferable
import UniformTypeIdentifiers

/// サイドバーのドラッグで運ぶもの。運ぶのは項目の id だけで、名前や本文はドラッグ用のペーストボード（他のアプリからも読める）に載せない。
/// 独自の型にしているので、他のアプリへ落としても受け取られず、他のアプリから落とされた文字列を移動と取り違えることもない
struct ItemReference: Codable, Transferable {
  let id: UUID

  static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .kinkoItemReference)
  }
}

extension UTType {
  /// Config/Info.plist の UTExportedTypeDeclarations で宣言している
  static let kinkoItemReference = UTType(exportedAs: "com.tomopu.kinko.item-reference")
}
