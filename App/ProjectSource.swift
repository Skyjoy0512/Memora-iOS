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
  var contentFingerprint: String?
  var createdAt = Date.now
  var updatedAt = Date.now
  var processingStatus = ProcessingStatus.pending
  // Optional so older sources remain readable without claiming full extraction.
  var textCoverage: TextCoverage?
  var privacy = RecordPrivacy()
  var errorInformation: String?
  var metadata: [String: String]?

  enum Kind: String, Codable, Sendable {
    case youtube, web, image, pdf, document, audio, note
  }

  enum ProcessingStatus: String, Codable, Sendable {
    case pending, processing, ready, unavailable, failed
  }

  enum TextCoverage: String, Codable, Sendable {
    case complete, partial
  }

  var fileReferences: [String] {
    [localFileReference, thumbnailReference, extractedTextReference].compactMap { $0 }
  }

  var canProvideText: Bool {
    processingStatus == .ready && extractedTextReference != nil
  }
}
