import Foundation

enum AIAttachmentFiles {
  static var directory: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("AIAttachments", isDirectory: true)
  }
  static let shared = ProjectSourceFiles(directory: directory)

  static func url(_ reference: String) throws -> URL {
    guard let url = ProjectSourceFiles.resolve(reference, in: directory) else { throw ProjectSourceFiles.Failure.invalidFile }
    return url
  }
}
