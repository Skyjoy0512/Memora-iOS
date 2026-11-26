import Foundation

/// A saved citation identifies retrieved evidence, rather than trusting IDs or
/// excerpts invented by the model. Targets are resolved again when opened.
struct ProjectCitation: Identifiable, Hashable, Codable, Sendable {
  var id = UUID()
  var target: Target
  var title: String
  var excerpt: String
  var page: Int?
  var time: TimeInterval?
  var recordedAt: Date?
  var photo: Photo?
  /// The source evidence this citation was read from. Older citations have no
  /// stamp and stay readable; a stamped citation is dropped once the source's
  /// text reference or content fingerprint changes.
  var evidenceReference: String?
  var evidenceFingerprint: String?

  var recordDateLabel: String? {
    recordedAt.map {
      let style = Date.FormatStyle(date: .numeric, time: .omitted).locale(Locale(identifier: "ja_JP"))
      return "記録日 \($0.formatted(style))"
    }
  }

  struct Photo: Hashable, Codable, Sendable {
    var name: String
    var byteCount: Int
    var modifiedAt: Date
    var textReadAt: Date
  }

  enum Target: Hashable, Codable, Sendable {
    case source(UUID)
    case meeting(UUID)
    case document(UUID)
    case task(UUID)

    var identifier: UUID {
      switch self {
      case .source(let id), .meeting(let id), .document(let id), .task(let id): id
      }
    }
  }
}
