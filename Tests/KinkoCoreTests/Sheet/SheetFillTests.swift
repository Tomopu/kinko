import Testing

@testable import KinkoCore

private func filled(_ inputs: [String], _ count: Int, direction: FillDirection = .down, increments: Bool = false) -> [String] {
  var sheet = Sheet(name: "Sheet1")
  let vertical = direction == .down || direction == .up
  let base = direction == .up ? 20 : (direction == .left ? 20 : 0)
  for (i, input) in inputs.enumerated() {
    sheet[vertical ? CellAddress(row: base + i, column: 0) : CellAddress(row: 0, column: base + i)] = input
  }
  let end = base + inputs.count - 1
  let source = vertical
    ? CellRange(CellAddress(row: base, column: 0), CellAddress(row: end, column: 0))
    : CellRange(CellAddress(row: 0, column: base), CellAddress(row: 0, column: end))
  sheet.fill(from: source, direction: direction, count: count, incrementsSingleNumbers: increments)
  return (1...count).map { step in
    switch direction {
    case .down: sheet[CellAddress(row: end + step, column: 0)]
    case .up: sheet[CellAddress(row: base - step, column: 0)]
    case .right: sheet[CellAddress(row: 0, column: end + step)]
    case .left: sheet[CellAddress(row: 0, column: base - step)]
    }
  }
}

@Test func singleNumberCopiesUnlessOptionIsHeld() {
  #expect(filled(["5"], 3) == ["5", "5", "5"])
  #expect(filled(["5"], 3, increments: true) == ["6", "7", "8"])
}

@Test func numberSeriesFollowTheTrend() {
  #expect(filled(["1", "2"], 3) == ["3", "4", "5"])
  #expect(filled(["10", "20", "30"], 2) == ["40", "50"])
  #expect(filled(["0.1", "0.2"], 2) == ["0.3", "0.4"])
  // 上へ広げると逆向きに続く
  #expect(filled(["3", "4"], 2, direction: .up) == ["2", "1"])
}

@Test func weekdaysMonthsAndLists() {
  #expect(filled(["月"], 7) == ["火", "水", "木", "金", "土", "日", "月"])
  #expect(filled(["月曜日", "水曜日"], 2) == ["金曜日", "日曜日"])
  #expect(filled(["MON"], 2) == ["TUE", "WED"])
  #expect(filled(["11月"], 3) == ["12月", "1月", "2月"])
  #expect(filled(["第4四半期"], 1) == ["第1四半期"])
  #expect(filled(["火"], 2, direction: .left) == ["月", "日"])
}

@Test func datesAdvanceByDay() {
  #expect(filled(["2026/10/30"], 3) == ["2026/10/31", "2026/11/01", "2026/11/02"])
  #expect(filled(["2026-1-30", "2026-2-6"], 1) == ["2026-2-13"])
  #expect(filled(["2024年2月28日"], 2) == ["2024年2月29日", "2024年3月1日"])
}

@Test func textWithNumbersCountsUp() {
  #expect(filled(["第1回"], 2) == ["第2回", "第3回"])
  #expect(filled(["item007"], 2, direction: .right) == ["item008", "item009"])
  #expect(filled(["A1", "A3"], 2) == ["A5", "A7"])
}

@Test func plainTextAndMixedRepeat() {
  #expect(filled(["りんご"], 2) == ["りんご", "りんご"])
  #expect(filled(["りんご", "1"], 3) == ["りんご", "1", "りんご"])
}

@Test func formulasCopyWithShiftedReferences() {
  var sheet = Sheet(name: "Sheet1")
  sheet[CellAddress("A1")!] = "1"
  sheet[CellAddress("B1")!] = "=A1*$A$1"
  sheet.fill(from: CellRange(CellAddress("B1")!), direction: .down, count: 2)
  #expect(sheet[CellAddress("B2")!] == "=A2*$A$1")
  #expect(sheet[CellAddress("B3")!] == "=A3*$A$1")
  sheet.fill(from: CellRange(CellAddress("B1")!), direction: .right, count: 1)
  #expect(sheet[CellAddress("C1")!] == "=B1*$A$1")
}

@Test func fillingAWideBlockWorksPerColumn() {
  var sheet = Sheet(name: "Sheet1")
  sheet[CellAddress("A1")!] = "1"
  sheet[CellAddress("A2")!] = "2"
  sheet[CellAddress("B1")!] = "月"
  sheet[CellAddress("B2")!] = "火"
  sheet.fill(from: CellRange(CellAddress("A1")!, CellAddress("B2")!), direction: .down, count: 1)
  #expect(sheet[CellAddress("A3")!] == "3")
  #expect(sheet[CellAddress("B3")!] == "水")
}

@Test func fillingUpCountsDown() {
  #expect(filled(["5"], 2, direction: .up, increments: true) == ["4", "3"])
  #expect(filled(["2026/11/01"], 1, direction: .up) == ["2026/10/31"])
  #expect(filled(["第2回"], 1, direction: .up) == ["第1回"])
}
