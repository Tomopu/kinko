import Foundation

/// セルの右下のつまみを引っぱったときの埋め方（オートフィル）
public enum FillDirection: Sendable {
  case down, up, right, left
}

extension Sheet {
  /// source の範囲を direction へ count セルぶん広げて埋める。
  /// 列（左右に広げるときは行）ごとに、並びが連番・曜日・日付などの続きものなら続きを、そうでなければ繰り返しを入れる。
  /// 数式は参照をずらして複製する。incrementsSingleNumbers は、数が 1 つだけのときにコピーではなく 1 ずつ増やすか（Excel の Ctrl / ここでは option）
  public mutating func fill(from source: CellRange, direction: FillDirection, count: Int, incrementsSingleNumbers: Bool = false) {
    guard count > 0 else { return }
    let vertical = direction == .down || direction == .up
    let forward = direction == .down || direction == .right
    let lines = vertical ? source.columns : source.rows
    let length = vertical ? source.rowCount : source.columnCount

    for line in lines {
      // 広げる向きに沿って並べる（上や左へ広げるときは、端から逆順にたどって「続き」を作る）
      let addresses: [CellAddress] = (0..<length).map { step in
        let offset = forward ? step : length - 1 - step
        return vertical
          ? CellAddress(row: source.start.row + offset, column: line)
          : CellAddress(row: line, column: source.start.column + offset)
      }
      let inputs = addresses.map { self[$0] }
      let series = FillSeries.extend(
        inputs, count: count, incrementsSingleNumbers: incrementsSingleNumbers, singleStep: forward ? 1 : -1)

      for step in 0..<count {
        let edge = forward ? (vertical ? source.end.row : source.end.column) : (vertical ? source.start.row : source.start.column)
        let position = edge + (forward ? step + 1 : -(step + 1))
        let target = vertical ? CellAddress(row: position, column: line) : CellAddress(row: line, column: position)
        guard target.isValid else { break }
        // 書式は繰り返しで写す（Excel と同じ）
        let origin = addresses[step % length]
        self[style: target] = self[style: origin]
        if let series {
          self[target] = series[step]
          continue
        }
        // 繰り返し：同じ位置の元のセルを、離れたぶんだけ参照をずらして写す
        let input = inputs[step % length]
        let rowOffset = target.row - origin.row
        let columnOffset = target.column - origin.column
        self[target] = CellInput.isFormula(input)
          ? Formula.shifted(input, rowOffset: rowOffset, columnOffset: columnOffset) : input
      }
    }
  }
}

/// 並びの続きを作る（オートフィルの中身）
enum FillSeries {
  /// inputs の続きを count 個。続きものでなければ nil（繰り返しで埋める）。
  /// singleStep は 1 つだけのときの増え方。上や左へ広げるときは -1 にして、「火」の上を「月」にする
  static func extend(_ inputs: [String], count: Int, incrementsSingleNumbers: Bool, singleStep: Int = 1) -> [String]? {
    let items = inputs.map(Item.init)
    guard let first = items.first, inputs.allSatisfy({ !CellInput.isFormula($0) }) else { return nil }

    switch first {
    case .number:
      let numbers = items.compactMap { if case .number(let x) = $0 { x } else { nil } }
      guard numbers.count == items.count else { return nil }
      if numbers.count == 1 && !incrementsSingleNumbers { return nil }
      // 2 つ以上なら、最小二乗法で引いた直線の続き（1, 2, 3 → 4, 5 / 2, 4 → 6, 8）。Excel と同じ
      let n = Double(numbers.count)
      var slope = Double(singleStep)
      var intercept = numbers[0]
      if numbers.count > 1 {
        let meanX = (n - 1) / 2
        let meanY = numbers.reduce(0, +) / n
        var numerator = 0.0
        var denominator = 0.0
        for (x, y) in numbers.enumerated() {
          numerator += (Double(x) - meanX) * (y - meanY)
          denominator += (Double(x) - meanX) * (Double(x) - meanX)
        }
        slope = numerator / denominator
        intercept = meanY - slope * meanX
      }
      return (0..<count).map { step in
        let value = intercept + slope * (n + Double(step))
        // 0.1 刻みなどで出る 0.30000000000000004 のような誤差を落とす
        return CellInput.number(Double(String(format: "%.12g", value)) ?? value)
      }

    case .date(_, let format):
      var days: [Int] = []
      for item in items {
        guard case .date(let day, let otherFormat) = item, otherFormat == format else { return nil }
        days.append(day)
      }
      let step = days.count > 1 ? days[1] - days[0] : singleStep
      return (0..<count).map { format.text(days.last! + step * ($0 + 1)) }

    case .listed(let list, _, _):
      var indices: [Int] = []
      for item in items {
        guard case .listed(let otherList, let index, _) = item, otherList == list else { return nil }
        indices.append(index)
      }
      let step = indices.count > 1 ? indices[1] - indices[0] : singleStep
      let words = FillSeries.lists[list]
      guard case .listed(_, _, let style) = first else { return nil }
      return (0..<count).map { k in
        let index = ((indices.last! + step * (k + 1)) % words.count + words.count) % words.count
        return style.apply(words[index])
      }

    case .numbered(let prefix, _, let width, let suffix):
      var numbers: [Int] = []
      for item in items {
        guard case .numbered(let p, let number, _, let s) = item, p == prefix, s == suffix else { return nil }
        numbers.append(number)
      }
      let step = numbers.count > 1 ? numbers[1] - numbers[0] : singleStep
      return (0..<count).map { k in
        let number = max(0, numbers.last! + step * (k + 1))
        return prefix + String(format: "%0\(width)d", number) + suffix
      }

    case .other:
      return nil
    }
  }

  /// 続きのある並び。Excel の「ユーザー設定リスト」の主なもの
  static let lists: [[String]] = [
    ["日", "月", "火", "水", "木", "金", "土"],
    ["日曜日", "月曜日", "火曜日", "水曜日", "木曜日", "金曜日", "土曜日"],
    ["日曜", "月曜", "火曜", "水曜", "木曜", "金曜", "土曜"],
    ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"],
    ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"],
    ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"],
    ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"],
    ["1月", "2月", "3月", "4月", "5月", "6月", "7月", "8月", "9月", "10月", "11月", "12月"],
    ["睦月", "如月", "弥生", "卯月", "皐月", "水無月", "文月", "葉月", "長月", "神無月", "霜月", "師走"],
    ["第1四半期", "第2四半期", "第3四半期", "第4四半期"],
    ["Q1", "Q2", "Q3", "Q4"],
    ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"],
    ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"],
  ]

  /// 英語の並びの大文字・小文字の書き方（最初のセルに合わせる）
  enum LetterCase: Equatable {
    case asListed, upper, lower

    init(_ text: String) {
      if text == text.uppercased() && text != text.lowercased() && text.count > 1 {
        self = .upper
      } else if text == text.lowercased() && text != text.uppercased() {
        self = .lower
      } else {
        self = .asListed
      }
    }

    func apply(_ word: String) -> String {
      switch self {
      case .asListed: word
      case .upper: word.uppercased()
      case .lower: word.lowercased()
      }
    }
  }

  /// 日付の書き方（2026/10/30、2026-1-5、2026年10月30日）。桁をそろえるかどうかも元に合わせる
  struct DateFormat: Equatable {
    var separator: String
    var padded: Bool

    func text(_ day: Int) -> String {
      let date = Date(timeIntervalSince1970: TimeInterval(day) * 86_400)
      let parts = FillSeries.calendar.dateComponents([.year, .month, .day], from: date)
      let (y, m, d) = (parts.year!, parts.month!, parts.day!)
      let month = padded ? String(format: "%02d", m) : String(m)
      let dayText = padded ? String(format: "%02d", d) : String(d)
      if separator == "年" { return "\(y)年\(month)月\(dayText)日" }
      return "\(y)\(separator)\(month)\(separator)\(dayText)"
    }
  }

  static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }()

  private static let datePattern = try! NSRegularExpression(pattern: #"^(\d{4})(?:([/-])(\d{1,2})\2(\d{1,2})|年(\d{1,2})月(\d{1,2})日)$"#)
  private static let numberedPattern = try! NSRegularExpression(pattern: #"^(.*?)(\d{1,9})(\D*)$"#)

  enum Item {
    case number(Double)
    /// 1970-01-01 からの日数
    case date(Int, DateFormat)
    case listed(list: Int, index: Int, LetterCase)
    /// 「第3回」「item007」のように数を含む文字列。最後の数を増やす
    case numbered(prefix: String, number: Int, width: Int, suffix: String)
    case other

    init(_ input: String) {
      if case .number(let number) = CellInput.literal(input), !input.hasPrefix("'") {
        self = .number(number)
        return
      }
      let text = input as NSString
      let whole = NSRange(location: 0, length: text.length)
      if let match = FillSeries.datePattern.firstMatch(in: input, range: whole) {
        func group(_ i: Int) -> String? {
          let range = match.range(at: i)
          return range.location == NSNotFound ? nil : text.substring(with: range)
        }
        let isKanji = group(5) != nil
        let monthText = (isKanji ? group(5) : group(3)) ?? ""
        let dayText = (isKanji ? group(6) : group(4)) ?? ""
        let components = DateComponents(year: Int(group(1) ?? ""), month: Int(monthText), day: Int(dayText))
        if let date = FillSeries.calendar.date(from: components),
          FillSeries.calendar.dateComponents([.month, .day], from: date).day == components.day
        {
          // 0 で始まる（01）か、月も日も 2 桁（10/30）なら 2 桁にそろえる
          let padded = monthText.hasPrefix("0") || dayText.hasPrefix("0") || (monthText.count == 2 && dayText.count == 2)
          let format = DateFormat(separator: isKanji ? "年" : (group(2) ?? "/"), padded: padded)
          self = .date(Int((date.timeIntervalSince1970 / 86_400).rounded()), format)
          return
        }
      }
      for (list, words) in FillSeries.lists.enumerated() {
        if let index = words.firstIndex(where: { $0.caseInsensitiveCompare(input) == .orderedSame }) {
          self = .listed(list: list, index: index, LetterCase(input))
          return
        }
      }
      if let match = FillSeries.numberedPattern.firstMatch(in: input, range: whole) {
        let digits = text.substring(with: match.range(at: 2))
        self = .numbered(
          prefix: text.substring(with: match.range(at: 1)), number: Int(digits) ?? 0,
          width: digits.hasPrefix("0") ? digits.count : 1, suffix: text.substring(with: match.range(at: 3)))
        return
      }
      self = .other
    }
  }
}
