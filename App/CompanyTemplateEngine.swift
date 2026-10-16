import Foundation

/// Edits only scalar text markers in existing XML parts, preserving every other part's bytes.
enum CompanyTemplateEngine {
  struct Analysis: Codable, Hashable {
    var placeholders: [String]
    var features: [String]
    var unsupportedSplitMarkers: Bool
    var isAvailable: Bool { !placeholders.isEmpty && !unsupportedSplitMarkers }
    var notice: String {
      "同じテキスト要素内の{{name}}だけ差し込めます。マスター・画像・書式・ノートは保持します。改ページ、文字あふれ、最終フォントはOfficeで確認してください。" +
        (unsupportedSplitMarkers ? "複数の文字要素に分割された差し込み欄は未対応です。" : "")
    }
  }
  enum Failure: LocalizedError {
    case unsupported, fields, tooLong
    var errorDescription: String? {
      switch self {
      case .unsupported: "このテンプレートの差し込み方式には未対応です。同じ文字要素内に{{title}}等を置いてください。署名・マクロ・埋め込み・外部参照には対応しません。"
      case .fields: "差し込み欄と値が一致しません。すべての欄を確認してください。"
      case .tooLong: "差し込み内容が長すぎます。PowerPointは1欄120文字、Wordは1欄10,000文字までです。"
      }
    }
  }
  private static let marker = try! NSRegularExpression(pattern: #"\{\{([A-Za-z][A-Za-z0-9_]{0,39})\}\}"#)
  private static let textElement = try! NSRegularExpression(pattern: #"<([A-Za-z_][A-Za-z0-9_]*:)?t\b[^>]*>([^<]*)</([A-Za-z_][A-Za-z0-9_]*:)?t>"#)

  static func analyze(_ data: Data, format: CompanyTemplate.Format) throws -> Analysis {
    var archive = try OfficeArchiveReader(data: data)
    var extraction = try OfficeArchiveReader(data: data)
    _ = try OfficeDocumentExtraction.read(archive: &extraction, extension: format.rawValue)
    var names = Set<String>(), features: [String] = []
    var split = false
    for path in archive.partNames {
      if path.contains("_xmlsignatures") || path.lowercased().contains("vbaproject") || path.contains("activeX/") || path.contains("embeddings/") { throw Failure.unsupported }
      if path.hasSuffix(".rels") {
        let xml = try OfficeXMLDocument(data: archive.read(path))
        if xml.nodes.contains(where: { $0.attributes["TargetMode"] == "External" }) { throw Failure.unsupported }
      }
      if path.contains("/media/") { features.append("画像: " + path) }
      if path.contains("slideMasters/") || path.contains("slideLayouts/") || path.contains("/theme/") || path.contains("notesSlides/") || path.contains("/header") || path.contains("/footer") { features.append("保持: " + path) }
      if path == "word/styles.xml" || path == "ppt/presentation.xml" || path.contains("/theme/") || path.contains("slideMasters/") || path.contains("slideLayouts/") {
        if path.hasSuffix(".xml") {
          let style = try OfficeXMLDocument(data: archive.read(path))
          for node in style.nodes where ["style", "rFonts", "latin", "ea", "srgbClr", "sldSz", "ph"].contains(node.name) {
            if features.count < 100 { features.append(node.name + ": " + node.attributes.sorted { $0.key < $1.key }.map { $0.key + "=" + $0.value }.joined(separator: " ")) }
          }
        }
      }
      guard mutablePart(path, format: format) else { continue }
      let bytes = try archive.read(path)
      let xml = try OfficeXMLDocument(data: bytes)
      let textNodes = xml.nodes.filter { $0.name == "t" }
      let together = textNodes.map(\.text).joined()
      let all = matches(together)
      let individual = textNodes.flatMap { matches($0.text) }
      if all.count != individual.count { split = true }
      names.formUnion(individual)
      for node in xml.nodes where ["pgSz", "pgMar", "rFonts", "tbl", "sectPr", "sldSz", "sp", "graphicFrame", "pic", "off", "ext", "ph"].contains(node.name) {
        if features.count < 100 { features.append(node.name + ": " + node.attributes.sorted { $0.key < $1.key }.map { $0.key + "=" + $0.value }.joined(separator: " ")) }
      }
    }
    return Analysis(placeholders: names.sorted(), features: Array(features.prefix(100)), unsupportedSplitMarkers: split)
  }

  static func fill(_ data: Data, format: CompanyTemplate.Format, values: [String: String]) throws -> Data {
    let analysis = try analyze(data, format: format)
    guard analysis.isAvailable else { throw Failure.unsupported }
    guard Set(values.keys) == Set(analysis.placeholders), values.count <= 30 else { throw Failure.fields }
    guard values.values.allSatisfy({ $0.count <= (format == .pptx ? 120 : 10_000) && !$0.contains("{{") }) else { throw Failure.tooLong }
    var archive = try OfficeArchiveReader(data: data), output = ZipArchive()
    for path in archive.partNames where !path.hasSuffix("/") {
      let original = try archive.read(path)
      guard mutablePart(path, format: format), var xml = String(data: original, encoding: .utf8) else { output.add(path, data: original); continue }
      let textRanges = textElement.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
      for element in textRanges.reversed() {
        guard let bounds = Range(element.range(at: 2), in: xml) else { throw Failure.unsupported }
        var text = String(xml[bounds])
        for name in analysis.placeholders { text = text.replacingOccurrences(of: "{{" + name + "}}", with: DOCXWriter.escape(values[name]!)) }
        xml.replaceSubrange(bounds, with: text)
      }
      _ = try OfficeXMLDocument(data: Data(xml.utf8))
      output.add(path, text: xml)
    }
    let result = output.data()
    var validate = try OfficeArchiveReader(data: result)
    _ = try OfficeDocumentExtraction.read(archive: &validate, extension: format.rawValue)
    guard try analyze(result, format: format).placeholders.isEmpty else { throw Failure.unsupported }
    return result
  }

  private static func mutablePart(_ path: String, format: CompanyTemplate.Format) -> Bool {
    if format == .docx { return path == "word/document.xml" || path.range(of: #"^word/(header|footer)\d+\.xml$"#, options: .regularExpression) != nil }
    return path.range(of: #"^ppt/slides/slide\d+\.xml$"#, options: .regularExpression) != nil
  }

  private static func matches(_ text: String) -> [String] {
    marker.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
      Range($0.range(at: 1), in: text).map { String(text[$0]) }
    }
  }
}
