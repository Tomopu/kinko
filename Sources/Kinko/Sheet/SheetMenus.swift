import AppKit
import KinkoCore

@MainActor
enum SheetMenus {
  static func cellMenu(target: NSResponder) -> NSMenu {
    let menu = NSMenu()
    add(menu, "切り取り", #selector(SheetCellsView.cut(_:)), target)
    add(menu, "コピー", #selector(SheetCellsView.copy(_:)), target)
    add(menu, "ペースト", #selector(SheetCellsView.paste(_:)), target)
    menu.addItem(.separator())
    add(menu, "上に行を挿入", #selector(SheetCellsView.insertRowsAbove(_:)), target)
    add(menu, "下に行を挿入", #selector(SheetCellsView.insertRowsBelow(_:)), target)
    add(menu, "左に列を挿入", #selector(SheetCellsView.insertColumnsLeft(_:)), target)
    add(menu, "右に列を挿入", #selector(SheetCellsView.insertColumnsRight(_:)), target)
    menu.addItem(.separator())
    add(menu, "行を削除", #selector(SheetCellsView.deleteSelectedRows(_:)), target)
    add(menu, "列を削除", #selector(SheetCellsView.deleteSelectedColumns(_:)), target)
    menu.addItem(.separator())
    add(menu, "セルを挿入して下へずらす", #selector(SheetCellsView.insertCellsShiftingDown(_:)), target)
    add(menu, "セルを挿入して右へずらす", #selector(SheetCellsView.insertCellsShiftingRight(_:)), target)
    add(menu, "セルを削除して上へ詰める", #selector(SheetCellsView.deleteCellsShiftingUp(_:)), target)
    add(menu, "セルを削除して左へ詰める", #selector(SheetCellsView.deleteCellsShiftingLeft(_:)), target)
    menu.addItem(.separator())
    add(menu, "内容を消去", #selector(SheetCellsView.delete(_:)), target)
    add(menu, "書式をクリア", #selector(SheetCellsView.clearFormats(_:)), target)
    return menu
  }

  static func rowMenu(target: NSResponder?) -> NSMenu {
    let menu = NSMenu()
    add(menu, "上に行を挿入", #selector(SheetCellsView.insertRowsAbove(_:)), target)
    add(menu, "下に行を挿入", #selector(SheetCellsView.insertRowsBelow(_:)), target)
    menu.addItem(.separator())
    add(menu, "行を削除", #selector(SheetCellsView.deleteSelectedRows(_:)), target)
    return menu
  }

  static func columnMenu(target: NSResponder?) -> NSMenu {
    let menu = NSMenu()
    add(menu, "左に列を挿入", #selector(SheetCellsView.insertColumnsLeft(_:)), target)
    add(menu, "右に列を挿入", #selector(SheetCellsView.insertColumnsRight(_:)), target)
    menu.addItem(.separator())
    add(menu, "列を削除", #selector(SheetCellsView.deleteSelectedColumns(_:)), target)
    return menu
  }

  private static func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ target: NSResponder?) {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = target
    menu.addItem(item)
  }

  static func drawHeaderLabel(_ text: String, in rect: NSRect, bold: Bool) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: bold ? .semibold : .regular)
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font, .foregroundColor: bold ? NSColor.labelColor : NSColor.secondaryLabelColor, .paragraphStyle: style,
    ]
    let height = ceil(font.ascender - font.descender)
    text.draw(
      with: NSRect(x: rect.minX, y: rect.minY + (rect.height - height) / 2 - 0.5, width: rect.width, height: height),
      options: .usesLineFragmentOrigin, attributes: attributes)
  }
}
