import Foundation

/// Replaces scalar markers within a paragraph, preserving every other part's bytes.
enum CompanyTemplateEngine {
  static let analysisVersion = 2
  struct Analysis: Codable, Hashable {
    var placeholders: [String]
    var features: [String]
    var unsupportedSplitMarkers: Bool
    var engineVersion: Int? = nil
    var isAvailable: Bool { !placeholders.isEmpty && placeholders.count <= 30 && !unsupportedSplitMarkers }
    var notice: String {
      "同じ段落内の{{name}}に30種類まで差し込めます。分割された欄は先頭文字の書式を引き継ぎます。マスター・画像・ノートは保持します。改ページ、文字あふれ、最終フォントはOfficeで確認してください。" +
        (engineVersion != CompanyTemplateEngine.analysisVersion ? "旧解析情報です。再解析で現在の対応範囲を確認してください。" : "") +
        (unsupportedSplitMarkers ? "段落・改行・フィールド等をまたぐ欄、変更履歴内の欄、不完全な欄は利用できません。" : "")
    }
  }
  enum Failure: LocalizedError {
    case unsupported, fields, tooLong, save, invalidText
    var errorDescription: String? {
      switch self {
      case .unsupported: "このテンプレートの差し込み方式には未対応です。同じ段落の通常の文字列に{{title}}等を置いてください。段落・改行・フィールド等をまたぐ欄、変更履歴、署名・マクロ・埋め込み・外部参照には対応しません。"
      case .fields: "差し込み欄は30種類までです。すべての欄と値が一致するか確認してください。"
      case .tooLong: "差し込み内容が長すぎます。PowerPointは1欄120文字、Wordは1欄10,000文字までです。"
      case .save: "解析結果を保存できませんでした。原本と登録情報は変更していません。"
      case .invalidText: "差し込み値にOffice XMLで使えない制御文字が含まれています。取り除いて再試行してください。"
      }
    }
  }

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
      let part = try OfficeTemplateTextPart(data: bytes, format: format)
      let xml = part.document
      split = split || part.hasUnsupportedMarkers
      names.formUnion(part.placeholders)
      for node in xml.nodes where ["pgSz", "pgMar", "rFonts", "tbl", "sectPr", "sldSz", "sp", "graphicFrame", "pic", "off", "ext", "ph"].contains(node.name) {
        if features.count < 100 { features.append(node.name + ": " + node.attributes.sorted { $0.key < $1.key }.map { $0.key + "=" + $0.value }.joined(separator: " ")) }
      }
    }
    guard names.count <= 30 else { throw Failure.fields }
    return Analysis(placeholders: names.sorted(), features: Array(features.prefix(100)), unsupportedSplitMarkers: split, engineVersion: analysisVersion)
  }

  static func fill(_ data: Data, format: CompanyTemplate.Format, values: [String: String]) throws -> Data {
    let analysis = try analyze(data, format: format)
    guard analysis.isAvailable else { throw Failure.unsupported }
    guard Set(values.keys) == Set(analysis.placeholders), values.count <= 30 else { throw Failure.fields }
    guard values.values.allSatisfy({ $0.count <= (format == .pptx ? 120 : 10_000) && !$0.contains("{{") }) else { throw Failure.tooLong }
    var archive = try OfficeArchiveReader(data: data), output = ZipArchive()
    var outputBytes = 0
    for path in archive.partNames where !path.hasSuffix("/") {
      let original = try archive.read(path)
      let filled = try mutablePart(path, format: format) ? OfficeTemplateTextPart(data: original, format: format).filling(values) : original
      guard filled.count <= OfficeArchiveReader.maximumReadBytes - outputBytes else { throw OfficeArchiveReader.Failure.limit }
      outputBytes += filled.count
      output.add(path, data: filled)
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

}
