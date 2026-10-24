import SwiftUI
import UIKit

@MainActor
enum MeetingSummaryPosterRenderer {
  static func render(_ content: MeetingSummaryPosterContent) throws -> UIImage {
    var fitted = content
    while true {
      let renderer = ImageRenderer(content: MeetingSummaryPosterCanvas(content: fitted))
      renderer.scale = 2
      renderer.isOpaque = true
      // Measure the native layout before allocating a bitmap for a long document.
      var measured = CGSize.zero
      renderer.render { size, _ in measured = size }
      guard measured.height > 0 else { throw CocoaError(.fileReadUnknown) }
      if measured.height <= 1200 {
        guard let image = renderer.uiImage else { throw CocoaError(.fileReadUnknown) }
        return image
      }
      guard fitted.reduceToFit() else { throw CocoaError(.fileReadTooLarge) }
    }
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
