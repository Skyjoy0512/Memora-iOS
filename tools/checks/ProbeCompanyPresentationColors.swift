import CoreGraphics
import ImageIO
import Foundation

/// Coordinates belong to the fictional b22 fixture, not arbitrary company files.
@main struct ProbeCompanyPresentationColors {
  static func main() throws {
    var results: [[String: Any]] = []
    for path in CommandLine.arguments.dropFirst() {
      let url = URL(fileURLWithPath: path)
      guard let context = CGContext(data: nil, width: 960, height: 540, bitsPerComponent: 8, bytesPerRow: 3840,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.fileReadCorruptFile) }
      context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: 960, height: 540))
      if url.pathExtension == "pdf" {
        guard let pdf = CGPDFDocument(url as CFURL), let page = pdf.page(at: 1) else { throw CocoaError(.fileReadCorruptFile) }
        context.drawPDFPage(page)
      } else {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CocoaError(.fileReadCorruptFile) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: 960, height: 540))
      }
      let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
      let locations = [("masterRectangle", 850, 10), ("masterLuminanceModulation", 730, 10),
        ("layoutLuminanceModulationAndOffset", 610, 10), ("firstEllipse", 267, 300), ("secondEllipse", 693, 300)]
      let samples: [[String: Any]] = locations.map { name, x, y in
        let offset = y * 3840 + x * 4
        return ["element": name, "x": x, "y": y, "sRGB": [Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2])]]
      }
      results.append(["file": path, "samples": samples, "status": "measured_not_rendering_approval"])
    }
    let output = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: output, as: UTF8.self))
  }
}
