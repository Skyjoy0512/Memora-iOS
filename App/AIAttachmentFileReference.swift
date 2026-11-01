import Foundation

/// Only the app-owned filename crosses launches; sandbox paths are not stable.
struct AIAttachmentFileReference: Codable, Hashable, Sendable {
  var id: UUID
  var name: String
  var fileName: String
  var additionalFiles: [AIAttachmentFileReference]?
  var originalURL: URL?

  init?(_ attachment: AIAttachment) {
    guard attachment.url.isFileURL, attachment.name.utf8.count <= 1_600,
          attachment.url.deletingLastPathComponent().lastPathComponent == "AIAttachments" else { return nil }
    id = attachment.id
    name = attachment.name
    fileName = attachment.url.lastPathComponent
    originalURL = attachment.originalURL
    additionalFiles = attachment.additionalFiles?.compactMap { file in
      AIAttachmentFileReference(AIAttachment(id: file.id, name: file.name, url: file.url, originalURL: file.originalURL))
    }
    guard (additionalFiles?.count ?? 0) == (attachment.additionalFiles?.count ?? 0) else { return nil }
    guard isValid else { return nil }
  }

  var isValid: Bool {
    Set([id] + (additionalFiles ?? []).map(\.id)).count == 1 + (additionalFiles?.count ?? 0) &&
      (originalURL.map { ["https", "http"].contains($0.scheme?.lowercased() ?? "") && $0.absoluteString.utf8.count <= 8_192 && $0.user == nil && $0.password == nil } ?? true) &&
      (additionalFiles?.count ?? 0) <= 9 && (additionalFiles ?? []).allSatisfy { $0.additionalFiles == nil && $0.isValid } &&
      !name.isEmpty && name.utf8.count <= 1_600 && !fileName.isEmpty && fileName.utf8.count <= 255
      && fileName != "." && fileName != ".." && !fileName.contains("/") && !fileName.contains("\\")
      && !fileName.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
  }

  func resolve() -> AIAttachment? {
    guard isValid else { return nil }
    let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("AIAttachments", isDirectory: true)
    let url = directory.appendingPathComponent(fileName)
    guard let directoryValues = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
          directoryValues.isDirectory == true, directoryValues.isSymbolicLink != true,
          let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
          values.isRegularFile == true, values.isSymbolicLink != true,
          let size = values.fileSize, size <= 50 * 1_024 * 1_024 else { return nil }
    let files = (additionalFiles ?? []).compactMap { $0.resolve() }
    guard files.count == (additionalFiles?.count ?? 0) else { return nil }
    return AIAttachment(id: id, name: name, url: url,
      additionalFiles: files.isEmpty ? nil : files.map { .init(id: $0.id, name: $0.name, url: $0.url, originalURL: $0.originalURL) }, originalURL: originalURL)
  }
}
