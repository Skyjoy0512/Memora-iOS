import Foundation

struct AIAttachment: Identifiable, Hashable, Sendable {
  var id: UUID
  var name: String
  var url: URL
  var additionalFiles: [File]?
  var originalURL: URL?
  var sourceMetadata: [String: String]? = nil

  var files: [File] { [File(id: id, name: name, url: url, originalURL: originalURL, sourceMetadata: sourceMetadata)] + (additionalFiles ?? []) }
  var displayName: String {
    let files = files
    if let metadata = sourceMetadata, Self.isValidSourceMetadata(metadata),
       files.allSatisfy({ $0.sourceMetadata?["partitionOriginalFingerprint"] == metadata["partitionOriginalFingerprint"] &&
         $0.sourceMetadata?["partitionOriginalName"] == metadata["partitionOriginalName"] }) {
      return metadata["partitionOriginalName"] ?? name
    }
    return files.count == 1 ? name : "\(files.count)件の資料"
  }

  static func isValidSourceMetadata(_ metadata: [String: String]?) -> Bool {
    guard let metadata else { return true }
    let keys: Set<String> = ["partitionOriginalFingerprint", "partitionOriginalName", "partitionOriginalPageCount", "partitionFirstPage", "partitionLastPage"]
    guard Set(metadata.keys) == keys,
          let fingerprint = metadata["partitionOriginalFingerprint"], fingerprint.utf8.count == 64,
          fingerprint.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
          let name = metadata["partitionOriginalName"], !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf8.count <= 1_600,
          let count = metadata["partitionOriginalPageCount"].flatMap(Int.init), (1...10_000).contains(count),
          let first = metadata["partitionFirstPage"].flatMap(Int.init),
          let last = metadata["partitionLastPage"].flatMap(Int.init),
          first >= 1, first <= last, last <= count else { return false }
    return true
  }

  mutating func append(_ attachment: AIAttachment) {
    let current = Set(files.map(\.id))
    additionalFiles = Array(((additionalFiles ?? []) + attachment.files.filter { !current.contains($0.id) }).prefix(9))
  }

  struct File: Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var url: URL
    var originalURL: URL?
    var sourceMetadata: [String: String]? = nil
  }
}
