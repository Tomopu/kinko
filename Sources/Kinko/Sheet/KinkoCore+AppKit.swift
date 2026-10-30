import AppKit
import KinkoCore

extension CellValue {
  var isNumber: Bool { if case .number = self { true } else { false } }
}

extension CellColor {
  var nsColor: NSColor {
    NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
  }

  /// 明るい色か（相対輝度で判断）。上に載せる文字を黒にするか白にするかに使う
  var isLight: Bool {
    0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue) > 150
  }
}
