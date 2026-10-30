import Foundation
import CoreGraphics

struct DocumentPDFFile {
  var url: URL
  private var didCommit = false
  var stagingURL: URL { url.appendingPathExtension("partial") }

  init(url: URL) throws {
    self.url = url
    guard !FileManager.default.fileExists(atPath: url.path),
          !FileManager.default.fileExists(atPath: stagingURL.path) else { throw DocumentPDFError.writeFailed }
  }

  mutating func commit(expectedPages: Int) throws {
    try Task.checkCancellation()
    guard let pdf = CGPDFDocument(stagingURL as CFURL), pdf.numberOfPages == expectedPages, expectedPages > 0 else {
      throw DocumentPDFError.writeFailed
    }
    try FileManager.default.moveItem(at: stagingURL, to: url)
    didCommit = true
    try Task.checkCancellation()
  }

  func discard() {
    try? FileManager.default.removeItem(at: stagingURL)
    if didCommit { try? FileManager.default.removeItem(at: url) }
  }
}
