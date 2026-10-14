import Foundation

/// Only the app-owned filename crosses launches; sandbox paths are not stable.
struct AIAttachmentFileReference: Codable, Sendable {
  var id: UUID
  var name: String
  var fileName: String

  init?(_ attachment: AIAttachment) {
    guard attachment.url.isFileURL, attachment.name.utf8.count <= 1_600,
          attachment.url.deletingLastPathComponent().lastPathComponent == "AIAttachments" else { return nil }
    id = attachment.id
    name = attachment.name
    fileName = attachment.url.lastPathComponent
    guard isValid else { return nil }
  }

  var isValid: Bool {
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
    return AIAttachment(id: id, name: name, url: url)
  }
}
