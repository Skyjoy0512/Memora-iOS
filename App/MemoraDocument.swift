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
  var companyTemplateVersion: Int?
  var artifactHistory: [DocumentArtifactRevision]?
  /// Missing revisions identify a legacy document and its original export (0).
  var contentRevision: Int?
  var artifactRevision: Int?
  var sourceProjectFileIDs: [UUID]?
  var sourceRecordIDs: [UUID]?
  var provenance: ArtifactProvenance?
  var sourceAnswerID: UUID?
  /// Optional so documents and backups written before presentation planning still decode.
  var presentationPlan: PresentationPlan?
  /// The evidence a generated deck was built from, kept with the deck so its
  /// scope and gaps can be reviewed after the conversation is gone.
  var presentationEvidence: PresentationEvidencePack?

  var hasOutdatedArtifact: Bool {
    artifactFileReference != nil && (artifactRevision ?? 0) != (contentRevision ?? 0)
  }

  var hasValidRevisions: Bool {
    (contentRevision ?? 0) >= 0 && (artifactRevision ?? 0) >= 0
      && (artifactRevision ?? 0) <= (contentRevision ?? 0)
      && (companyTemplateVersion.map { $0 > 0 && companyTemplateID != nil } ?? true)
      && (artifactHistory.map { history in
        history.count <= DocumentArtifactRevision.maximumHistory && Set(history.map(\.id)).count == history.count &&
          Set(history.map(\.fileReference)).count == history.count && history.allSatisfy {
            $0.isValid && $0.contentRevision <= (contentRevision ?? 0) && $0.fileReference != artifactFileReference
          }
      } ?? true)
  }

  var artifactFileReferences: [String] { [artifactFileReference].compactMap { $0 } + (artifactHistory ?? []).map(\.fileReference) }

  /// An outline edit does not prove that a company Office file was rewritten.
  /// Keep the last successful export and attribution until a replacement exists.
  func editing(title: String, body: String, at date: Date = .now) -> Self? {
    guard hasValidRevisions, (contentRevision ?? 0) < Int.max else { return nil }
    var edited = self
    edited.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    switch kind {
    case .document:
      edited.markdown = body
    case .slides:
      if body != DocumentSlide.outline(of: slides) {
        // An outline cannot represent tables, graph coordinates or provenance.
        // Structured documents use the slide editor instead of losing those fields.
        guard slides.allSatisfy({ $0.composition == nil }) else { return nil }
        edited.slides = DocumentSlide.slides(fromOutline: body)
      }
    }
    edited.presentationPlan = presentationPlan?.reconciled(with: edited.slides)
    guard edited.title != self.title || edited.markdown != markdown || edited.slides != slides else { return self }
    edited.contentRevision = (contentRevision ?? 0) + 1
    edited.updatedAt = date
    return edited
  }

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
