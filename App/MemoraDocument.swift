import Foundation

/// A document the agent (or the person) made from the records: a written
/// document in markdown, or a set of slides.
struct MemoraDocument: Identifiable, Hashable, Codable, Sendable {
  var id = UUID()
  var title: String
  var kind: MemoraDocumentKind
  /// The body of a `.document`. Empty for slides.
  var markdown = ""
  /// The slides of a `.slides` document. Empty for a written document.
  var slides: [DocumentSlide] = []
  var spaceID: UUID?
  var createdAt = Date.now
  var updatedAt = Date.now
  /// Set on a weekly review: the first day of the week it covers.
  var weekStart: Date?
  /// When the document was first opened, so a new review can be pointed out
  /// until it has been read.
  var openedAt: Date?
  var generatedReviewMarkdown: String?
  var artifactFileReference: String?
  var artifactFormat: String?
  var companyTemplateID: UUID?
  var sourceProjectFileIDs: [UUID]?
  var sourceRecordIDs: [UUID]?
  var provenance: ArtifactProvenance?

  var displayTitle: String {
    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "無題の\(kind.label)" : title
  }

  /// A short line for lists: the first words of the body, or the slide count.
  var preview: String {
    switch kind {
    case .document:
      let text = markdown
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#-*> ").union(.whitespaces)) }
        .filter { !$0.isEmpty && !$0.hasPrefix("|") }
        .prefix(3)
        .joined(separator: " ")
      return String(text.prefix(120))
    case .slides:
      return companyTemplateID != nil && slides.isEmpty ? "会社テンプレートのPowerPoint" : "\(slides.count)枚のスライド"
    }
  }

  /// A file name the share sheet can use, without characters a file system
  /// refuses.
  var exportFileName: String {
    let cleaned = displayTitle
      .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
      .joined(separator: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? kind.label : String(cleaned.prefix(60))
  }

  /// The document as plain text, for sharing into notes or a message.
  var plainText: String {
    switch kind {
    case .document:
      return "# \(displayTitle)\n\n\(markdown)"
    case .slides:
      return "# \(displayTitle)\n\n" + DocumentSlide.outline(of: slides)
    }
  }
}
