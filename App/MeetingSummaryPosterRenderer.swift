import SwiftUI
import UIKit

@MainActor
enum MeetingSummaryPosterRenderer {
  static func render(_ content: MeetingSummaryPosterContent) throws -> UIImage {
    let renderer = ImageRenderer(content: MeetingSummaryPosterCanvas(content: content))
    renderer.scale = 2
    renderer.isOpaque = true
    guard let image = renderer.uiImage else { throw CocoaError(.fileReadUnknown) }
    return image
  }

  static func export(_ image: UIImage) throws -> URL {
    guard let data = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
    var url = FileManager.default.temporaryDirectory
      .appendingPathComponent("Memora-summary-" + UUID().uuidString + ".png")
    do {
      try data.write(to: url, options: [.atomic, .completeFileProtection])
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try url.setResourceValues(values)
      return url
    } catch {
      ArtifactExportFile.removeTemporary([url])
      throw error
    }
  }
}
