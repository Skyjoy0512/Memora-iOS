import Foundation
import UniformTypeIdentifiers

/// Every entry point classifies and extracts the same way; saving and access
/// policy remain owned by the destination rather than by external content.
enum SourceIntake {
  static func kind(for url: URL) -> ProjectSource.Kind {
    let suffix = url.pathExtension.lowercased()
    if suffix == "pdf" { return .pdf }
    if let type = UTType(filenameExtension: suffix) {
      if type.conforms(to: .audio) { return .audio }
      if type.conforms(to: .movie) { return .video }
      if type.conforms(to: .image) { return .image }
    }
    return .document
  }

  #if !MEMORA_HOST_CHECKS
  static func extract(_ url: URL, vocabulary: [String] = [], speechLocale: Locale? = nil) async throws -> ProjectSourceExtractionResult {
    try await SourceProcessingQueue.shared.perform {
      switch kind(for: url) {
      case .audio, .video:
        return try await SourceMediaExtraction.extract(url, vocabulary: vocabulary, speechLocale: speechLocale)
      default:
        return try await ProjectSourceExtraction.extract(url)
      }
    }
  }
  #endif
}
