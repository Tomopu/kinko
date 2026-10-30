import sys
from datetime import datetime
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Border, Side, Alignment
from openpyxl.styles.colors import Color
from openpyxl.formatting.rule import CellIsRule

out = sys.argv[1]
wb = Workbook()
wb.calculation.fullCalcOnLoad = True  # openpyxl は計算結果を持たないので、Excel に開いたとき計算させる

thin = Side(style="thin")
grid = Border(left=thin, right=thin, top=thin, bottom=thin)
F = lambda **k: Font(name="Arial", **k)

# --- 1 枚目 ---
ws = wb.active
ws.title = "家計簿"
ws["A1"] = "Kinko 読み込みテスト（この行は結合セル・14pt）"
ws["A1"].font = F(bold=True, size=14)
ws.merge_cells("A1:F1")

headers = ["日付", "曜日", "項目", "金額", "税込", "メモ"]
header_fill = PatternFill("solid", fgColor=Color(theme=4, tint=0.7999816888943144))  # テーマの色（青・明るさ 80%）
for i, h in enumerate(headers):
    c = ws.cell(row=3, column=1 + i, value=h)
    c.font = F(bold=True)
    c.fill = header_fill
    c.alignment = Alignment(horizontal="center")
    c.border = grid

rows = [
    (datetime(2026, 10, 1), "木", "食費", 1200, "スーパー"),
    (datetime(2026, 10, 2), "金", "交通費", 460, "斜体のメモ"),
    (datetime(2026, 10, 3), "土", "日用品", 980, "下線のメモ"),
    (datetime(2026, 10, 4), "日", "書籍", 1500, "007"),
    (datetime(2026, 10, 5), "月", "返金", -300, "取り消し線"),
]
for r, (d, wd, item, amount, memo) in enumerate(rows, start=4):
    ws.cell(row=r, column=1, value=d).number_format = "yyyy/m/d"
    ws.cell(row=r, column=2, value=wd).alignment = Alignment(horizontal="center")
    ws.cell(row=r, column=3, value=item)
    a = ws.cell(row=r, column=4, value=amount)
    a.number_format = "[$¥-ja-JP]#,##0"
    e = ws.cell(row=r, column=5, value=f"=ROUND(D{r}*(1+$I$4),0)")
    e.number_format = "[$¥-ja-JP]#,##0"
    m = ws.cell(row=r, column=6, value=memo)
    m.number_format = "@"  # 007 を文字列のまま持つ
    for col in range(1, 7):
        ws.cell(row=r, column=col).border = grid
        if ws.cell(row=r, column=col).font.name != "Arial":
            ws.cell(row=r, column=col).font = F()
ws["F5"].font = F(italic=True)
ws["F6"].font = F(underline="single")
ws["F7"].alignment = Alignment(horizontal="right")
ws["F8"].font = F(strike=True)
ws["D8"].font = F(color="FFC00000")  # マイナスは赤い字
ws["G4"].fill = PatternFill("solid", fgColor=Color(theme=9, tint=0.5999938962981048))  # 値のない、塗りだけのセル

ws["A9"], ws["D9"], ws["E9"] = "合計", "=SUM(D4:D8)", "=SUM(E4:E8)"
for c in ("A9", "D9", "E9"):
    ws[c].font = F(bold=True)
    ws[c].border = Border(top=Side(style="thin"), bottom=Side(style="double"))
ws["D9"].number_format = ws["E9"].number_format = "[$¥-ja-JP]#,##0"
ws["A10"], ws["D10"] = "平均", "=AVERAGE(D4:D8)"
ws["D10"].number_format = "#,##0.00"
ws["A11"], ws["D11"] = "件数", '=COUNT(D4:D8)&"件"'
ws["A12"], ws["D12"] = "判定", '=IF(D9>3000,"予算オーバー","予算内")'

ws["I3"] = "税率"
ws["I3"].font = F(bold=True)
ws["I4"] = 0.1
ws["I4"].number_format = "0%"
ws["I4"].font = F(color="FFC00000", bold=True)
ws["I4"].fill = PatternFill("solid", fgColor="FFFFF2CC")
ws["I6"] = "別シートの合計"
ws["I7"] = "='売上 2026'!B6"
ws["I7"].number_format = "#,##0"

ws["A14"] = "小数"
ws["C14"] = 2.675
ws["C14"].number_format = "0.00"
ws["D14"] = "=ROUND(C14,2)"
ws["A15"] = "桁区切り"
ws["C15"] = 1234567.891
ws["C15"].number_format = "#,##0.0"
ws["A16"] = "百分率"
ws["C16"] = 0.125
ws["C16"].number_format = "0.0%"
ws["A17"] = "時刻つき"
ws["C17"] = datetime(2026, 10, 30, 14, 5)
ws["C17"].number_format = "yyyy/m/d h:mm"
ws["A18"] = "真偽値"
ws["C18"] = True

ws["A20"], ws["C20"] = "VLOOKUP", '=VLOOKUP("書籍",C4:D8,2,FALSE)'
ws["A21"], ws["C21"] = "SUMIF", '=SUMIF(C4:C8,"食費",D4:D8)'
ws["A22"], ws["C22"] = "COUNTIF", '=COUNTIF(D4:D8,">=1000")'
ws["A23"], ws["C23"] = "IFERROR", '=IFERROR(1/0,"ゼロ除算")'
ws["A24"], ws["C24"] = "文字の結合", '=CONCATENATE(C4,"と",C5)&"!"'

ws["A26"] = "このセルは折り返し・上揃え（Kinko は折り返しを扱わない）"
ws["A26"].alignment = Alignment(wrap_text=True, vertical="top")
ws.row_dimensions[26].height = 32

# 罫線の種類と色の見本
ws["H10"] = "罫線の見本"
ws["H10"].font = F(bold=True)
samples = [
    ("H11", "破線・青の外枠", Side(style="dashed", color="FF0070C0")),
    ("H13", "太線・赤", Side(style="thick", color="FFC00000")),
    ("H15", "一点鎖線・緑", Side(style="dashDot", color="FF00B050")),
    ("H17", "点線", Side(style="dotted")),
    ("H19", "二重線", Side(style="double")),
]
for cell, label, side in samples:
    ws[cell] = label
    ws[cell].border = Border(left=side, right=side, top=side, bottom=side)
ws["J11"] = "上揃え"
ws["J11"].alignment = Alignment(vertical="top")
ws["J13"] = "上下中央"
ws["J13"].alignment = Alignment(vertical="center")
ws["J15"] = "下揃え（既定）"
for row in (11, 13, 15):
    ws.row_dimensions[row].height = 36
ws["J17"] = "折り返し：列の幅で次の行へ送って、セルの中に全部表示する"
ws["J17"].alignment = Alignment(wrap_text=True, vertical="center")

# 条件付き書式（Kinko は扱わない）：1000 以上を薄い赤に
ws.conditional_formatting.add("D4:D8", CellIsRule(operator="greaterThanOrEqual", formula=["1000"], fill=PatternFill("solid", bgColor="FFFFC7CE")))

for col, width in {"A": 14, "B": 7, "C": 13, "D": 12, "E": 12, "F": 14, "H": 18, "I": 16, "J": 16}.items():
    ws.column_dimensions[col].width = width

# --- 2 枚目（名前に日本語と空白） ---
s2 = wb.create_sheet("売上 2026")
s2["A1"], s2["B1"] = "月", "売上"
for c in ("A1", "B1"):
    s2[c].font = F(bold=True)
    s2[c].border = Border(bottom=Side(style="thin"))
for i, (m, v) in enumerate([("1月", 120000), ("2月", 98000), ("3月", 143500), ("4月", 110250)], start=2):
    s2.cell(row=i, column=1, value=m)
    s2.cell(row=i, column=2, value=v).number_format = "#,##0"
s2["A6"], s2["B6"] = "合計", "=SUM(B2:B5)"
s2["A6"].font = s2["B6"].font = F(bold=True)
s2["B6"].number_format = "#,##0"
s2.column_dimensions["B"].width = 12

# --- 3 枚目：見比べるための一覧 ---
s3 = wb.create_sheet("確認リスト")
s3["A1"] = "Kinko に読み込んだあと、Excel の表示と見比べる項目（このシートは説明用）"
s3["A1"].font = F(bold=True)
checks = [
    ("家計簿!A4:A8", "日付（日付の書式）", "2026/10/01 のような文字列になる"),
    ("家計簿!D4:E9", "通貨 [$¥-ja-JP]#,##0", "¥1,200 と表示される"),
    ("家計簿!E4:E8", "数式 ROUND と $I$4（絶対参照）", "数式のまま読め、¥1,320 などになる"),
    ("家計簿!F7", "文字列の 007", "0 が消えない"),
    ("家計簿!F5 / F6 / F8", "斜体・下線・取り消し線", "それぞれ反映される"),
    ("家計簿!D8 / I4", "赤い文字", "赤く表示される"),
    ("家計簿!A3:F3", "テーマの色（青 80%）の塗り・太字・中央揃え", "薄い青・太字・中央"),
    ("家計簿!G4", "値のない塗りだけのセル（テーマの色）", "薄いオレンジが残る"),
    ("家計簿!A3:F8", "格子の罫線、9 行目の上罫線と二重下罫線", "罫線が付く（二重線は細い線になる）"),
    ("家計簿!I7", "別シート '売上 2026' の参照", "471,750 になる"),
    ("家計簿!C14:D14", "2.675 と ROUND", "2.68（2.67 にならない）"),
    ("家計簿!C15 / C16", "桁区切り・百分率", "1,234,567.9 と 12.5%"),
    ("家計簿!C17", "時刻つきの日付", "2026/10/30 14:05"),
    ("家計簿!C20:C24", "VLOOKUP・SUMIF・COUNTIF・IFERROR・CONCATENATE", "1500・1200・2・ゼロ除算・食費と交通費!"),
    ("家計簿!A1", "結合セル・14pt（Kinko は扱わない）", "結合は解け、A1 に文字が入る"),
    ("家計簿!A26", "折り返し・上揃え", "折り返して上に寄る（行は Excel の高さ）"),
    ("家計簿!H11:H19", "罫線の種類と色（破線・太線・一点鎖線・点線・二重線）", "同じ種類・色の線になる"),
    ("家計簿!J11:J15", "縦の配置（上・中央・下）と行の高さ 36", "上・中央・下に寄る"),
    ("家計簿!J17", "折り返し・上下中央", "折り返して全部見え、行が自動で高くなる"),
    ("家計簿!D4:D8", "条件付き書式（Kinko は扱わない）", "色は付かないが値は残る"),
]
for i, h in enumerate(["場所", "入っているもの", "Kinko での期待"], start=1):
    c = s3.cell(row=3, column=i, value=h)
    c.font = F(bold=True)
    c.fill = PatternFill("solid", fgColor="FFDDEBF7")
    c.border = grid
for r, row in enumerate(checks, start=4):
    for i, v in enumerate(row, start=1):
        c = s3.cell(row=r, column=i, value=v)
        c.font = F()
        c.border = grid
for col, width in {"A": 20, "B": 42, "C": 40}.items():
    s3.column_dimensions[col].width = width

for sheet in wb.worksheets:
    for row in sheet.iter_rows():
        for c in row:
            if c.font is not None and c.font.name != "Arial":
                f = c.font
                c.font = Font(name="Arial", bold=f.bold, italic=f.italic, underline=f.underline, strike=f.strike, color=f.color, size=f.size)
wb.save(out)
print("saved", out)
