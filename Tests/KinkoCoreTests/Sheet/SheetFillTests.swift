import Testing

@testable import KinkoCore

@Suite("つまみでの複製")
struct SheetFillTests {
  /// inputs を縦（左右へ広げるときは横）に並べて direction へ count 個広げ、広げた先のセルの入力を近い順に返す。
  /// 上・左へも広げられるよう、並べ始めは 21 行目（U 列）にする
  private func filled(_ inputs: [String], _ count: Int, direction: FillDirection = .down, increments: Bool = false) -> [String] {
    let vertical = direction == .down || direction == .up
    let base = direction == .up || direction == .left ? 20 : 0
    let at = { (i: Int) in vertical ? CellAddress(row: base + i, column: 0) : CellAddress(row: 0, column: base + i) }
    var sheet = Sheet(name: "Sheet1")
    for (i, input) in inputs.enumerated() { sheet[at(i)] = input }

    sheet.fill(from: CellRange(at(0), at(inputs.count - 1)), direction: direction, count: count, incrementsSingleNumbers: increments)

    let forward = direction == .down || direction == .right
    return (1...count).map { sheet[at(forward ? inputs.count - 1 + $0 : -$0)] }
  }

  @Test("数 1 つは複製し、option を押しているときだけ 1 ずつ増やす")
  func singleNumber() {
    // Given: 5 だけのセル
    let source = ["5"]

    // When: 下へ 3 つ広げる（option なし・あり）
    let copied = filled(source, 3)
    let counted = filled(source, 3, increments: true)

    // Then
    #expect(copied == ["5", "5", "5"])
    #expect(counted == ["6", "7", "8"])
  }

  @Test("並びの決まりに沿って続ける", arguments: [
    // 数は直線の傾きで
    (["1", "2"], FillDirection.down, ["3", "4", "5"]),
    (["10", "20", "30"], .down, ["40", "50"]),
    (["0.1", "0.2"], .down, ["0.3", "0.4"]),
    // 曜日・月・リストは一巡すると最初に戻る
    (["月"], .down, ["火", "水", "木", "金", "土", "日", "月"]),
    (["月曜日", "水曜日"], .down, ["金曜日", "日曜日"]),
    (["MON"], .down, ["TUE", "WED"]),
    (["11月"], .down, ["12月", "1月", "2月"]),
    (["第4四半期"], .down, ["第1四半期"]),
    // 日付は 1 日ずつ（2 つあればその間隔で）。書き方は元に合わせる
    (["2026/10/30"], .down, ["2026/10/31", "2026/11/01", "2026/11/02"]),
    (["2026-1-30", "2026-2-6"], .down, ["2026-2-13"]),
    (["2024年2月28日"], .down, ["2024年2月29日", "2024年3月1日"]),
    // 番号の付いた文字列は番号を増やす（0 埋めの桁は保つ）
    (["第1回"], .down, ["第2回", "第3回"]),
    (["item007"], .right, ["item008", "item009"]),
    (["A1", "A3"], .down, ["A5", "A7"]),
    // ただの文字列や、決まりのない並びはくり返す
    (["りんご"], .down, ["りんご", "りんご"]),
    (["りんご", "1"], .down, ["りんご", "1", "りんご"]),
    // 上・左へは逆向きに続く
    (["3", "4"], .up, ["2", "1"]),
    (["火"], .left, ["月", "日"]),
    (["2026/11/01"], .up, ["2026/10/31"]),
    (["第2回"], .up, ["第1回"]),
  ])
  func series(source: [String], direction: FillDirection, expected: [String]) {
    // Given: source を並べたセル
    // When: direction へ expected の数だけ広げる
    let result = filled(source, expected.count, direction: direction)

    // Then
    #expect(result == expected)
  }

  @Test("上へ広げると、option ありの数は 1 ずつ減る")
  func singleNumberUp() {
    // Given / When: 5 から上へ 2 つ、option を押して広げる
    let result = filled(["5"], 2, direction: .up, increments: true)

    // Then
    #expect(result == ["4", "3"])
  }

  @Test("数式は参照をずらして複製する（$ の付いた参照は動かさない）")
  func formulas() {
    // Given
    var sheet = Sheet(cells: ["A1": "1", "B1": "=A1*$A$1"])

    // When: B1 を下へ 2 つ、右へ 1 つ広げる
    sheet.fill(from: range("B1"), direction: .down, count: 2)
    sheet.fill(from: range("B1"), direction: .right, count: 1)

    // Then
    #expect(sheet["B2"] == "=A2*$A$1")
    #expect(sheet["B3"] == "=A3*$A$1")
    #expect(sheet["C1"] == "=B1*$A$1")
  }

  @Test("幅のある範囲は列ごとに続ける")
  func wideBlock() {
    // Given: A 列に数、B 列に曜日
    var sheet = Sheet(cells: ["A1": "1", "A2": "2", "B1": "月", "B2": "火"])

    // When
    sheet.fill(from: range("A1:B2"), direction: .down, count: 1)

    // Then
    #expect(sheet["A3"] == "3")
    #expect(sheet["B3"] == "水")
  }
}
