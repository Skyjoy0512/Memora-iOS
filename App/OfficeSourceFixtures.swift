#if DEBUG
import Foundation

/// Synthetic text packages and the existing Memora PowerPoint exporter. Kept
/// out of release builds and never mixed with the person's source content.
enum OfficeSourceFixtures {
  static func write(in root: URL) throws -> [URL] {
    let relationship = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    func package(main: String, contentType: String) -> ZipArchive {
      var archive = ZipArchive()
      archive.add("_rels/.rels", text: """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="main" Type="\(relationship)/officeDocument" Target="\(main)"/></Relationships>
        """)
      archive.add("[Content_Types].xml", text: """
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/\(main)" ContentType="application/vnd.openxmlformats-officedocument.\(contentType).main+xml"/></Types>
        """)
      return archive
    }
    var word = package(main: "word/document.xml", contentType: "wordprocessingml.document")
    word.add("word/document.xml", text: """
      <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>MEMORA OFFICE FIXTURE</w:t></w:r></w:p><w:p><w:r><w:t>資料を確認する。担当: Ken</w:t></w:r></w:p></w:body></w:document>
      """)
    let docx = root.appendingPathComponent("QA-Word-会議の決定事項と次回までの確認事項.docx")
    try word.data().write(to: docx)
    var workbook = package(main: "xl/workbook.xml", contentType: "spreadsheetml.sheet")
    workbook.add("xl/workbook.xml", text: """
      <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="\(relationship)"><sheets><sheet name="検証データ" sheetId="1" r:id="sheet"/></sheets></workbook>
      """)
    workbook.add("xl/_rels/workbook.xml.rels", text: """
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="sheet" Type="\(relationship)/worksheet" Target="worksheets/sheet1.xml"/></Relationships>
      """)
    workbook.add("xl/worksheets/sheet1.xml", text: """
      <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>MEMORA OFFICE FIXTURE</t></is></c><c r="B1"><f>SUM(40,2)</f><v>42</v></c></row></sheetData></worksheet>
      """)
    let xlsx = root.appendingPathComponent("QA-Excel.xlsx")
    try workbook.data().write(to: xlsx)
    let slides = MemoraDocument(title: "Office検証", kind: .slides, slides: [
      DocumentSlide(title: "MEMORA OFFICE FIXTURE", bullets: ["最初のスライド"], notes: "NOT PARSED NOTES"),
      DocumentSlide(title: "SECOND SLIDE", bullets: ["次の確認事項"])
    ])
    let pptx = root.appendingPathComponent("QA-PowerPoint.pptx")
    try PPTXWriter.data(for: slides).write(to: pptx)
    return [docx, pptx, xlsx]
  }
}
#endif
