import Foundation

@main struct DocumentArtifactChecks {
  static func main() throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let doc = MemoraDocument(title: "提案書 {{title}}", kind: .document, markdown: "# 背景\n{{body}}\n\n| 項目 | 内容 |\n| --- | --- |\n| 費用 | 未確認 |")
    let word = try DOCXWriter.data(for: doc)
    let slides = MemoraDocument(title: "報告", kind: .slides, slides: [DocumentSlide(title: "{{title}}", bullets: ["{{body}}"], notes: "保存メモ")])
    let powerpoint = PPTXWriter.data(for: slides)
    for (format, bytes) in [(CompanyTemplate.Format.docx, word), (.pptx, powerpoint)] {
      let analysis = try CompanyTemplateEngine.analyze(bytes, format: format)
      precondition(analysis.placeholders == ["body", "title"] && analysis.isAvailable)
      let output = try CompanyTemplateEngine.fill(bytes, format: format, values: ["title": "日本語 & 検証", "body": "決定した内容 <編集可能>"])
      var before = try OfficeArchiveReader(data: bytes), after = try OfficeArchiveReader(data: output)
      precondition(before.partNames == after.partNames)
      for name in before.partNames {
        let first = try before.read(name), second = try after.read(name)
        if !["word/document.xml", "ppt/slides/slide1.xml"].contains(name) { precondition(first == second) }
      }
      var reloaded = try OfficeArchiveReader(data: output)
      let extracted = try OfficeDocumentExtraction.read(archive: &reloaded, extension: format.rawValue)
      precondition(extracted.blocks.map(\.text).joined().contains("日本語 & 検証"))
      try output.write(to: root.appendingPathComponent("generated." + format.rawValue))
      do { _ = try CompanyTemplateEngine.fill(bytes, format: format, values: ["title": "不足"]); preconditionFailure() } catch {}
      if format == .pptx {
        do { _ = try CompanyTemplateEngine.fill(bytes, format: format, values: ["title": String(repeating: "長", count: 121), "body": "内容"]); preconditionFailure() } catch {}
      }
    }
    var archive = try OfficeArchiveReader(data: word), split = ZipArchive()
    for name in archive.partNames {
      let data = try archive.read(name)
      if name == "word/document.xml" {
        split.add(name, text: String(decoding: data, as: UTF8.self).replacingOccurrences(of: "{{title}}", with: "{{ti</w:t></w:r><w:r><w:t>tle}}"))
      } else { split.add(name, data: data) }
    }
    let analysis = try CompanyTemplateEngine.analyze(split.data(), format: .docx)
    precondition(analysis.unsupportedSplitMarkers && !analysis.isAvailable)
    do { _ = try CompanyTemplateEngine.analyze(Data("broken".utf8), format: .docx); preconditionFailure() } catch {}
    var long = doc; long.title = "長文"; long.markdown = (0..<300).map { "日本語の複数ページ用段落 \($0)" }.joined(separator: "\n")
    try DOCXWriter.data(for: long).write(to: root.appendingPathComponent("long.docx"))
    print("DocumentArtifactChecks: passed (real DOCX/PPTX, Japanese, tables, long flow, XML escaping, unchanged masters/styles/theme, split/overflow/corruption rejection, reload; final Office rendering unverified)")
  }
}
