import Foundation

/// Immutable file references keep earlier exports reachable and backed up.
struct DocumentArtifactRevision: Identifiable, Codable, Hashable, Sendable {
  enum Format: String, Codable, Sendable { case pptx = "PPTX", docx = "DOCX" }
  static let maximumHistory = 100

  var id = UUID()
  var fileReference: String
  var format: Format
  var contentRevision: Int
  var companyTemplateID: UUID?
  var companyTemplateVersion: Int?
  /// This is when the file was retained, not an inferred original export date.
  var retainedAt = Date.now

  var isValid: Bool {
    !fileReference.isEmpty && fileReference.utf8.count <= 255 &&
      ![".", ".."].contains(fileReference) && !fileReference.contains("/") && !fileReference.contains("\\") &&
      !fileReference.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) &&
      (fileReference as NSString).pathExtension.lowercased() == format.rawValue.lowercased() &&
      contentRevision >= 0 && retainedAt.timeIntervalSinceReferenceDate.isFinite &&
      (companyTemplateVersion.map { $0 > 0 && companyTemplateID != nil } ?? true)
  }
}
