import Foundation

@testable import KinkoCore

// テストで繰り返す書き方。セルを "A1" のような文字列で指せるようにして、`CellAddress("A1")!` を毎回書かずに済ませる

/// A1 形式の位置。書き間違いはその場で落とす
func address(_ a1: String) -> CellAddress { CellAddress(a1)! }

/// "A1" か "A1:B3" 形式の範囲
func range(_ a1: String) -> CellRange {
  let corners = a1.split(separator: ":").map { CellAddress($0)! }
  return CellRange(corners[0], corners.last!)
}

func style(_ build: (inout CellStyle) -> Void) -> CellStyle {
  var style = CellStyle()
  build(&style)
  return style
}

func color(_ hex: String) -> CellColor { CellColor(hex: hex)! }

extension Sheet {
  /// A1 形式で入力を並べたシート
  init(name: String = "Sheet1", cells: [String: String]) {
    self.init(name: name)
    for (a1, input) in cells { self[address(a1)] = input }
  }

  subscript(_ a1: String) -> String {
    get { self[address(a1)] }
    set { self[address(a1)] = newValue }
  }

  subscript(style a1: String) -> CellStyle {
    get { self[style: address(a1)] }
    set { self[style: address(a1)] = newValue }
  }
}
