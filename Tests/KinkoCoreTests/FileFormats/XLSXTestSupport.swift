import Foundation

@testable import KinkoCore

/// 部品を並べて .xlsx を作る（読み込みのエラーを試すため）
func package(sheetXML: String, workbookXML: String? = nil, stylesXML: String? = nil) throws -> Data {
  let ns = #"xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships""#
  let rels = #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>"#
  return try ZipWriter.archive([
    ("xl/styles.xml", Data(#"<styleSheet \#(ns)>\#(stylesXML ?? "")</styleSheet>"#.utf8)),
    ("xl/workbook.xml", Data((workbookXML ?? #"<workbook \#(ns)><sheets><sheet name="S" sheetId="1" r:id="rId1"/></sheets></workbook>"#).utf8)),
    ("xl/_rels/workbook.xml.rels", Data(rels.utf8)),
    ("xl/worksheets/sheet1.xml", Data(#"<worksheet \#(ns)><sheetData>\#(sheetXML)</sheetData></worksheet>"#.utf8)),
  ])
}
