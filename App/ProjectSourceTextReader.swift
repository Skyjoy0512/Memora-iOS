import Foundation

enum ProjectSourceTextReader {
  static let maximumBytes = 2 * 1024 * 1024

  static func read(_ reference: String, in directory: URL? = nil) throws -> [ProjectSourceText] {
    try Task.checkCancellation()
    guard let url = ProjectSourceFiles.resolve(reference, in: directory) else { throw ProjectSourceFiles.Failure.invalidFile }
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true,
          let size = values.fileSize, size <= maximumBytes else { throw ProjectSourceFiles.Failure.invalidFile }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
    guard data.count <= maximumBytes else { throw ProjectSourceFiles.Failure.invalidFile }
    try Task.checkCancellation()
    let blocks = try JSONDecoder().decode([ProjectSourceText].self, from: data)
    try Task.checkCancellation()
    return blocks
  }

  static func readAsync(_ reference: String, in directory: URL? = nil) async throws -> [ProjectSourceText] {
    let job = Task.detached(priority: .utility) { try read(reference, in: directory) }
    return try await withTaskCancellationHandler {
      try await job.value
    } onCancel: {
      job.cancel()
    }
  }
}
