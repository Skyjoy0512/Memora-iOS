import CoreGraphics
import Foundation

enum CompanyPresentationPDF {
  static func data(for preview: CompanyPresentationPreview) throws -> Data {
    guard (1...65).contains(preview.pages.count), preview.pages.allSatisfy({ $0.elements != nil }) else { throw CompanyPresentationPreview.Failure.unsupported }
    let output = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 960, height: 540)
    let metadata = [kCGPDFContextTitle: "追加ページのみ（原本ページは含みません）", kCGPDFContextCreator: "Memora"] as CFDictionary
    guard let consumer = CGDataConsumer(data: output), let pdf = CGContext(consumer: consumer, mediaBox: &box, metadata) else { throw CocoaError(.fileWriteUnknown) }
    do { for page in preview.pages {
      try Task.checkCancellation()
      pdf.beginPDFPage(nil)
      pdf.setFillColor(PresentationDrawing.color("FFFFFF")); pdf.fill(box)
      pdf.saveGState(); pdf.translateBy(x: 0, y: 540); pdf.scaleBy(x: 1, y: -1)
      PresentationDrawing.draw(page.elements!, in: pdf)
      pdf.restoreGState(); pdf.endPDFPage()
    } } catch { pdf.closePDF(); throw error }
    pdf.closePDF()
    return output as Data
  }
}
