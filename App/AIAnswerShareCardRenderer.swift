import SwiftUI
import UIKit
import Foundation

/// Renders the share card offscreen so the preview and the shared file are the
/// same image.
@MainActor
enum AIAnswerShareCardRenderer {
  static func render(_ content: AIAnswerShareContent) -> UIImage? {
    let renderer = ImageRenderer(content: AIAnswerShareCard(content: content))
    renderer.scale = 3
    renderer.isOpaque = true
    return renderer.uiImage
  }

  static func export(_ image: UIImage) throws -> URL {
    guard let data = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
    var url = FileManager.default.temporaryDirectory
      .appendingPathComponent("Memoraの回答-" + stamp() + ".png")
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

  /// A readable file name in the share sheet, unique enough for one export.
  private static func stamp() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: .now)
  }
}
