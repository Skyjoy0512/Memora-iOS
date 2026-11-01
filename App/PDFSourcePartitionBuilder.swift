import Foundation
import PDFKit

/// Keeps a single native part document alive at a time. Oversized candidates
/// are removed before their original page range is bisected and written again.
final class PDFSourcePartitionBuilder {
  private(set) var parts: [PDFSourcePartition.Part] = []
  private var document: PDFDocument
  private var directory: URL
  private(set) var outputBytes = 0

  init(document: PDFDocument, directory: URL) {
    self.document = document
    self.directory = directory
  }

  func append(_ range: ClosedRange<Int>) throws {
    try Task.checkCancellation()
    guard parts.count < PDFSourcePartition.maximumParts else { throw PDFSourcePartitionFailure.partLimit }
    let target = directory.appendingPathComponent("pages-\(range.lowerBound)-\(range.upperBound).pdf")
    let bytes = try autoreleasepool {
      let part = PDFDocument()
      part.documentAttributes = textualAttributes()
      for originalNumber in range {
        try Task.checkCancellation()
        try autoreleasepool {
          guard let original = document.page(at: originalNumber - 1),
                let page = original.copy() as? PDFPage else { throw PDFSourcePartitionFailure.invalidFile }
          // Form fields share document-level state and cannot be copied into
          // independent parts while retaining their original behavior/signature.
          if page.annotations.contains(where: { $0.type == "Widget" }) { throw PDFSourcePartitionFailure.interactiveDocument }
          part.insert(page, at: part.pageCount)
        }
      }
      try Task.checkCancellation()
      // No page rasterization, OCR, JPEG conversion or image downscaling.
      let options: [PDFDocumentWriteOption: Any] = [
        .burnInAnnotationsOption: false,
        .saveTextFromOCROption: false,
        .saveImagesAsJPEGOption: false,
        .optimizeImagesForScreenOption: false
      ]
      try PDFSourcePartitionStaging.ensureWriteCapacity(in: directory)
      guard part.write(to: target, withOptions: options) else { throw PDFSourcePartitionFailure.writeFailed }
      try Task.checkCancellation()
      let properties = try target.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
      guard properties.isRegularFile == true, properties.isSymbolicLink != true,
            let bytes = properties.fileSize, bytes > 0 else { throw PDFSourcePartitionFailure.writeFailed }
      return bytes
    }
    if bytes > PDFSourcePartition.maximumPartBytes {
      try FileManager.default.removeItem(at: target)
      guard range.lowerBound < range.upperBound else { throw PDFSourcePartitionFailure.singlePageTooLarge(range.lowerBound) }
      // Even the smallest legal result needs one file for each side.
      guard parts.count + 2 <= PDFSourcePartition.maximumParts else { throw PDFSourcePartitionFailure.partLimit }
      let midpoint = range.lowerBound + (range.upperBound - range.lowerBound) / 2
      try append(range.lowerBound...midpoint)
      try append((midpoint + 1)...range.upperBound)
      return
    }
    guard bytes <= PDFSourcePartition.maximumOutputBytes - outputBytes else { throw PDFSourcePartitionFailure.aggregateLimit }
    // Reopen the written file rather than trusting a successful writer return.
    // The reader sees native local pages 1...N; original numbering stays outside.
    let readable = try autoreleasepool { () throws -> Bool in
      guard let written = PDFDocument(url: target), !written.isLocked, !written.isEncrypted else { return false }
      return written.pageCount == range.count
    }
    guard readable else { throw PDFSourcePartitionFailure.writeFailed }
    try Task.checkCancellation()
    outputBytes += bytes
    parts.append(.init(url: target, firstPage: range.lowerBound, lastPage: range.upperBound))
  }

  private func textualAttributes() -> [AnyHashable: Any] {
    let original = document.documentAttributes ?? [:]
    var result: [AnyHashable: Any] = [:]
    let keys: [PDFDocumentAttribute] = [.titleAttribute, .authorAttribute, .subjectAttribute,
      .creatorAttribute, .producerAttribute, .keywordsAttribute, .creationDateAttribute, .modificationDateAttribute]
    for key in keys {
      let value = original[key]
      if let text = value as? String { result[key] = text }
      else if let strings = value as? [String] { result[key] = strings }
      else if let date = value as? Date { result[key] = date }
    }
    return result
  }
}
