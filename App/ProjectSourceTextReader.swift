import Foundation

enum ProjectSourceTextReader {
  static let maximumBytes = 2 * 1024 * 1024

  static func read(_ reference: String) throws -> [ProjectSourceText] {
    guard let url = ProjectSourceFiles.resolve(reference),
          let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
          size <= maximumBytes else { throw ProjectSourceFiles.Failure.invalidFile }
    return try JSONDecoder().decode([ProjectSourceText].self, from: Data(contentsOf: url))
  }
}
