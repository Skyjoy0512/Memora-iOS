import Foundation

struct AIAttachment: Identifiable, Hashable, Sendable {
  var id: UUID
  var name: String
  var url: URL
  var additionalFiles: [File]?
  var originalURL: URL?

  var files: [File] { [File(id: id, name: name, url: url, originalURL: originalURL)] + (additionalFiles ?? []) }
  var displayName: String { files.count == 1 ? name : "\(files.count)件の資料" }

  mutating func append(_ attachment: AIAttachment) {
    let current = Set(files.map(\.id))
    additionalFiles = Array(((additionalFiles ?? []) + attachment.files.filter { !current.contains($0.id) }).prefix(9))
  }

  struct File: Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var url: URL
    var originalURL: URL?
  }
}
