import Foundation
import ImageIO
import UIKit
import Vision

/// Reads the words written in a stored photo, on this device. Nothing leaves the
/// phone and no result is invented: a read that fails returns nil and is tried
/// again later.
enum MediaTextRecognizer {
  static func read(photoNamed name: String) async -> String? {
    guard let url = MediaFiles.photoURL(name) else { return nil }
    let job = Task.detached(priority: .utility) { () -> String? in
      guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceThumbnailMaxPixelSize: 1_600,
              kCGImageSourceCreateThumbnailWithTransform: true
            ] as CFDictionary) else { return nil }
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      request.recognitionLanguages = ["ja-JP", "en-US"]
      guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil else { return nil }
      let text = (request.results ?? [])
        .compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: "\n")
      return String(text.prefix(MediaIndexEntry.maximumText))
    }
    return await withTaskCancellationHandler {
      await job.value
    } onCancel: {
      job.cancel()
    }
  }
}
