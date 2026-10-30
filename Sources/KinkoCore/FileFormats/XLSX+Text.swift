import Foundation

/// 文字列と数式の変換（XML の文字参照、新しい関数の _xlfn. など）
extension XLSX {
  /// XML の特殊文字を文字参照にし、XML 1.0 で使えない文字（タブ・改行以外の制御文字など）は捨てる。
  /// タブ・改行も文字参照にする（属性の中では空白に、CR は本文でも LF に置き換えられてしまうため）
  static func escape(_ text: String) -> String {
    var result = ""
    result.unicodeScalars.reserveCapacity(text.unicodeScalars.count)
    for scalar in text.unicodeScalars {
      switch scalar {
      case "&": result += "&amp;"
      case "<": result += "&lt;"
      case ">": result += "&gt;"
      case "\"": result += "&quot;"
      case "\t": result += "&#9;"
      case "\n": result += "&#10;"
      case "\r": result += "&#13;"
      case _ where scalar.value < 0x20 || scalar.value == 0xFFFE || scalar.value == 0xFFFF: continue
      default: result.unicodeScalars.append(scalar)
      }
    }
    return result
  }

  /// セルの文字列を書く。文字列の中に "_x000D_" のような並びがあると読む側が 1 文字に戻してしまうので、
  /// 先頭の "_" を "_x005F_"（"_" そのもの）にしておく
  static func escapeText(_ text: String) -> String {
    let units = Array(text.utf16)
    var result: [UInt16] = []
    result.reserveCapacity(units.count)
    for (index, unit) in units.enumerated() {
      if unit == 0x5F, escapedUnit(units, index) != nil { result += Array("_x005F".utf16) }
      result.append(unit)
    }
    return escape(String(decoding: result, as: UTF16.self))
  }

  /// "_xHHHH_" を 1 文字に戻す（Excel は XML に書けない文字や改行の CR をこの形で書く）
  static func unescapeText(_ text: String) -> String {
    guard text.contains("_x") else { return text }
    let units = Array(text.utf16)
    var result: [UInt16] = []
    result.reserveCapacity(units.count)
    var index = 0
    while index < units.count {
      if let unit = escapedUnit(units, index) {
        result.append(unit)
        index += 7
      } else {
        result.append(units[index])
        index += 1
      }
    }
    // サロゲートの片割れだけが残った場合は U+FFFD になる
    return String(decoding: result, as: UTF16.self)
  }

  /// units[index...] が "_xHHHH_" ならその値
  private static func escapedUnit(_ units: [UInt16], _ index: Int) -> UInt16? {
    guard index + 7 <= units.count, units[index] == 0x5F, units[index + 1] == 0x78, units[index + 6] == 0x5F else { return nil }
    return UInt16(String(decoding: units[(index + 2)..<(index + 6)], as: UTF16.self), radix: 16)
  }

  /// Excel 2010 以降に増えた関数。ファイルの中では "_xlfn." を付けて書く決まり（付けないと古い関数名として扱われ #NAME? になる）
  static let newFunctions: Set<String> = ["CONCAT", "TEXTJOIN", "IFS", "SWITCH", "MAXIFS", "MINIFS", "XLOOKUP"]

  /// 書くとき: 新しい関数の名前の前に "_xlfn." を付ける
  static func addFunctionPrefixes(_ formula: String) -> String {
    rewriteOutsideLiterals(formula) { characters, index in
      // 名前の途中（"MYCONCAT(" や "_xlfn.CONCAT("）は対象にしない
      if index > 0, isNameCharacter(characters[index - 1]) { return nil }
      var end = index
      while end < characters.count, isNameCharacter(characters[end]) { end += 1 }
      guard end < characters.count, characters[end] == "(", newFunctions.contains(String(characters[index..<end]).uppercased())
      else { return nil }
      return ("_xlfn." + String(characters[index..<end]), end - index)
    }
  }

  /// 読むとき: "_xlfn." "_xlws." を外す（Kinko の数式は付けない名前で書く）
  static func removeFunctionPrefixes(_ formula: String) -> String {
    rewriteOutsideLiterals(formula) { characters, index in
      guard characters[index] == "_", index + 6 <= characters.count else { return nil }
      let prefix = String(characters[index..<(index + 6)])
      return prefix == "_xlfn." || prefix == "_xlws." ? ("", 6) : nil
    }
  }

  /// ほかのブック（ファイル）を参照する式か。Excel はブックの間でセルを写すと "[1]Sheet1!A1" や
  /// "'[2]売上 2026'!B6" のような式を書く（[1] は xl/externalLinks/externalLink1.xml、つまりディスク上の別のファイル）。
  /// Kinko は金庫の外のファイルを読みに行かない（暗号化されていない場所に触れない・そもそもそこにない）ので、
  /// こういう式は計算せず、Excel が保存したときの値（キャッシュ値）を値として取り込む。
  ///
  /// 見分け方: "..." の文字列の中は見ない。'...' のシート名の中の "[" はすべて外部参照（シート名に [ ] は使えない）。
  /// 引用符の外では、名前の途中でない "[数字]" の後に名前と "!" が続くもの（"[1]Sheet1!" や "[1]!名前"）。
  /// テーブルの構造化参照（"表1[2024]" や "表1[[#This Row],[列]]"）は名前の途中か、角かっこの中なので外部参照にしない
  static func hasExternalReference(_ formula: String) -> Bool {
    let characters = Array(formula)
    var index = 0
    var depth = 0
    while index < characters.count {
      switch characters[index] {
      case "\"":
        index += 1
        while index < characters.count, characters[index] != "\"" { index += 1 }
      case "'":
        index += 1
        while index < characters.count, characters[index] != "'" {
          if characters[index] == "[" { return true }
          index += 1
        }
      case "[":
        if depth == 0, index == 0 || !(isNameCharacter(characters[index - 1]) || characters[index - 1] == "]") {
          var end = index + 1
          while end < characters.count, characters[end].isASCII, characters[end].isNumber { end += 1 }
          if end > index + 1, end < characters.count, characters[end] == "]" {
            var name = end + 1
            while name < characters.count, isNameCharacter(characters[name]) { name += 1 }
            if name < characters.count, characters[name] == "!" { return true }
          }
        }
        depth += 1
      case "]": depth = max(0, depth - 1)
      default: break
      }
      index += 1
    }
    return false
  }

  private static func isNameCharacter(_ character: Character) -> Bool {
    character.isLetter || character.isNumber || character == "_" || character == "."
  }

  /// 文字列の定数（"..."）とシート名（'...'）の外だけで、replace が返す文字列に置き換える
  /// replace は (置き換える文字列, 飛ばす文字数) か、置き換えないなら nil を返す
  private static func rewriteOutsideLiterals(
    _ formula: String, _ replace: ([Character], Int) -> (String, Int)?
  ) -> String {
    let characters = Array(formula)
    var result = ""
    var quote: Character?
    var index = 0
    while index < characters.count {
      let character = characters[index]
      if let open = quote {
        // 閉じた直後に同じ引用符が続く（"" や ''）場合も、閉じて開き直すだけなので正しく扱える
        if character == open { quote = nil }
      } else if character == "\"" || character == "'" {
        quote = character
      } else if let (replacement, length) = replace(characters, index) {
        result += replacement
        index += length
        continue
      }
      result.append(character)
      index += 1
    }
    return result
  }

  /// Excel のシート名の決まりに合わせる: 31 文字まで、[]:*?/\ は使えない、先頭と末尾に ' は置けない、大文字小文字を区別せず重複しない
  static func sheetNames(_ names: [String]) -> [String] {
    var result: [String] = []
    for (index, name) in names.enumerated() {
      var base = String(
        String.UnicodeScalarView(
          name.unicodeScalars.compactMap { scalar -> Unicode.Scalar? in
            if scalar.value < 0x20 || scalar.value == 0xFFFE || scalar.value == 0xFFFF { return nil }
            return "[]:*?/\\".unicodeScalars.contains(scalar) ? "_" : scalar
          }))
      while base.hasPrefix("'") { base.removeFirst() }
      while base.hasSuffix("'") { base.removeLast() }
      base = truncated(base, toUTF16Count: 31)
      if base.isEmpty || base.caseInsensitiveCompare("History") == .orderedSame { base = "Sheet\(index + 1)" }
      var candidate = base
      var number = 2
      while result.contains(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
        let suffix = " (\(number))"
        candidate = truncated(base, toUTF16Count: 31 - suffix.utf16.count) + suffix
        number += 1
      }
      result.append(candidate)
    }
    return result
  }

  /// Excel の 31 文字は UTF-16 の単位で数える。文字の途中では切らない
  private static func truncated(_ text: String, toUTF16Count limit: Int) -> String {
    var result = ""
    var count = 0
    for character in text {
      count += character.utf16.count
      if count > limit { break }
      result.append(character)
    }
    return result
  }
}
