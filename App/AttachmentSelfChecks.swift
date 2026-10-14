#if DEBUG
import Foundation
import UIKit

enum AttachmentSelfChecks {
  static func run() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("AttachmentChecks-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    func prepared(_ url: URL) -> PreparedAIAttachment {
      AIAttachmentText.readContent(AIAttachment(id: UUID(), name: url.lastPathComponent, url: url))
    }
    let pdf = root.appendingPathComponent("pages.pdf")
    let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 300))
    let pdfData = renderer.pdfData { context in
      for index in 1...21 {
        context.beginPage()
        ("PAGE \(index) MEMORA FIXTURE" as NSString).draw(at: CGPoint(x: 30, y: 30),
          withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
      }
    }
    try pdfData.write(to: pdf)
    let projectPDF = try ProjectSourceExtraction.read(pdf)
    try require(projectPDF.blocks.count == 20 && projectPDF.blocks.last?.page == 20, "PDF page limit")
    let attachmentPDF = prepared(pdf)
    try require(attachmentPDF.text?.contains("PAGE 1 MEMORA FIXTURE") == true && attachmentPDF.notice?.contains("20") == true, "shared PDF extraction")

    let image = root.appendingPathComponent("text.png")
    let imageData = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 240)).pngData { context in
      UIColor.white.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 800, height: 240))
      ("MEMORA OCR 12345" as NSString).draw(at: CGPoint(x: 40, y: 80),
        withAttributes: [.font: UIFont.systemFont(ofSize: 48), .foregroundColor: UIColor.black])
    }
    try imageData.write(to: image)
    let ocr = prepared(image)
    try require(ocr.text?.contains("MEMORA") == true && ocr.notice?.contains("OCR") == true, "local image OCR")
    let noThumbnail = try ProjectSourceExtraction.read(image, includesThumbnail: false)
    try require(noThumbnail.thumbnail == nil, "ephemeral attachment thumbnail allocation")

    let invalid = root.appendingPathComponent("invalid.pdf")
    try Data("not a PDF".utf8).write(to: invalid)
    try require(prepared(invalid).text == nil && prepared(invalid).failure != nil, "invalid PDF fallback")
    let audio = root.appendingPathComponent("recording.m4a")
    try Data([0]).write(to: audio)
    try require(prepared(audio).text == nil && prepared(audio).failure?.contains("文字起こし") == true, "unsupported audio")
    let huge = root.appendingPathComponent("large.pdf")
    FileManager.default.createFile(atPath: huge.path, contents: nil)
    let handle = try FileHandle(forWritingTo: huge)
    try handle.truncate(atOffset: UInt64(ProjectSourceFiles.maximumFileBytes + 1))
    try handle.close()
    try require(prepared(huge).text == nil && prepared(huge).failure?.contains("50MB") == true, "file size before parsing")
  }

  private static func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw Failure.check(message) }
  }

  private enum Failure: LocalizedError {
    case check(String)
    var errorDescription: String? {
      if case .check(let message) = self { return message }
      return nil
    }
  }
}
#endif
