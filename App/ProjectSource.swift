import Foundation

/// Only newly imported sources live here; existing recordings and documents
/// remain in their original stores and are projected into workspace rows.
struct ProjectSource: Identifiable, Hashable, Codable, Sendable {
  var id = UUID()
  var projectID: UUID?
  var kind: Kind
  var title: String
  var originalURL: URL?
  var localFileReference: String?
  var thumbnailReference: String?
  var extractedTextReference: String?
  var captionFileReference: String?
  var contentFingerprint: String?
  var createdAt = Date.now
  var updatedAt = Date.now
  var processingStatus = ProcessingStatus.pending
  // Optional so older sources remain readable without claiming full extraction.
  var textCoverage: TextCoverage?
  var privacy = RecordPrivacy()
  var errorInformation: String?
  var metadata: [String: String]?
  var acquiredAt: Date?
  var pageCount: Int?
  var unreadablePages: [Int]?
  var omittedPages: [Int]?
  var ocrPages: [Int]?
  var ocrFailedPages: [Int]?
  var resumePage: Int?
  var summary: String?
  var summaryStatus: ProcessingStatus?
  var summaryTextReference: String?
  var summaryAttemptTextReference: String?
  var summaryUpdatedAt: Date?
  var summaryError: String?
  var summaryHistory: [String]?
  var summaryOptions: SourceSummaryOptions?
  var revisions: [Revision]?

  enum Kind: String, Codable, Sendable {
    case youtube, web, image, pdf, document, audio, note, video
  }

  enum ProcessingStatus: String, Codable, Sendable {
    case pending, processing, ready, unavailable, failed
  }

  enum TextCoverage: String, Codable, Sendable {
    case complete, partial
  }

  var fileReferences: [String] {
    [localFileReference, thumbnailReference, extractedTextReference, captionFileReference].compactMap { $0 }
      + (revisions ?? []).flatMap { [$0.originalFileReference, $0.textReference].compactMap { $0 } }
  }

  var canProvideText: Bool {
    processingStatus == .ready && extractedTextReference != nil
  }

  // A summary finishing does not change the original passages sent to Ask AI.
  // Moves, privacy edits and replacement originals must still revoke the read.
  func hasSameReadableEvidence(as other: Self) -> Bool {
    id == other.id && projectID == other.projectID && kind == other.kind && title == other.title &&
      originalURL == other.originalURL && localFileReference == other.localFileReference &&
      extractedTextReference == other.extractedTextReference && contentFingerprint == other.contentFingerprint &&
      processingStatus == other.processingStatus && textCoverage == other.textCoverage && privacy == other.privacy &&
      errorInformation == other.errorInformation
  }

  mutating func retainRevision() {
    guard let extractedTextReference, revisions?.last?.textReference != extractedTextReference else { return }
    revisions = Array(((revisions ?? []) + [Revision(acquiredAt: acquiredAt ?? updatedAt,
      originalFileReference: localFileReference, textReference: extractedTextReference,
      fingerprint: contentFingerprint, summary: summary)]).suffix(3))
  }

  struct Revision: Codable, Hashable, Sendable {
    var acquiredAt: Date
    var originalFileReference: String?
    var textReference: String
    var fingerprint: String?
    var summary: String?
  }
}
