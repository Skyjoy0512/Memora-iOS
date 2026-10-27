import AppKit
import Foundation

@main
struct ComparePresentationRenders {
  static func main() throws {
    let args = CommandLine.arguments
    let native = URL(fileURLWithPath: args[1]), office = URL(fileURLWithPath: args[2]), output = URL(fileURLWithPath: args[3])
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let files = try FileManager.default.contentsOfDirectory(at: native, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    var results: [[String: Any]] = []
    for (index, file) in files.enumerated() {
      let id = file.deletingPathExtension().lastPathComponent
      let ql = office.appendingPathComponent(id + ".pptx.png")
      guard let a = bitmap(file), let b = bitmap(ql) else { throw CocoaError(.fileReadCorruptFile) }
      let pixels = 960 * 540
      var difference = 0.0, nativeBlue = 0, officeBlue = 0, matchedBlue = 0
      let diff = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 960, pixelsHigh: 540, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
      for y in 0..<540 {
        for x in 0..<960 {
          let ac = a.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!, bc = b.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
          let d = (abs(ac.redComponent - bc.redComponent) + abs(ac.greenComponent - bc.greenComponent) + abs(ac.blueComponent - bc.blueComponent)) / 3
          difference += d
          let aBlue = ac.blueComponent > 0.6 && ac.redComponent < 0.4 && ac.greenComponent < 0.65
          let bBlue = bc.blueComponent > 0.6 && bc.redComponent < 0.4 && bc.greenComponent < 0.65
          if aBlue { nativeBlue += 1 }; if bBlue { officeBlue += 1 }; if aBlue && bBlue { matchedBlue += 1 }
          diff.setColor(NSColor(deviceRed: min(1, d * 4), green: 0, blue: 0, alpha: 1), atX: x, y: y)
        }
      }
      let blueRecall = nativeBlue == 0 ? 1.0 : Double(matchedBlue) / Double(nativeBlue)
      results.append(["id": id, "meanPixelDifference": difference / Double(pixels), "nativeBluePixels": nativeBlue,
        "officeBluePixels": officeBlue, "blueOverlapRecall": blueRecall,
        "status": "measured_not_visual_approval"])
      try diff.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(id + "-difference.png"))
      // Six pairs per sheet, with a named native/Quick Look row for visual inspection.
      let sheet = index / 6, row = index % 6
      let contactURL = output.appendingPathComponent("comparison-\(sheet).png")
      let image: NSImage
      if row == 0 { image = NSImage(size: NSSize(width: 1200, height: 2160)) }
      else { image = NSImage(contentsOf: contactURL)! }
      image.lockFocus()
      if row == 0 { NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1200, height: 2160).fill() }
      let top = 2160 - CGFloat(row + 1) * 360
      (id + "  Native PDF / Quick Look PPTX").draw(at: NSPoint(x: 12, y: top + 340), withAttributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
      NSImage(contentsOf: file)!.draw(in: NSRect(x: 0, y: top, width: 600, height: 337.5))
      NSImage(contentsOf: ql)!.draw(in: NSRect(x: 600, y: top, width: 600, height: 337.5))
      image.unlockFocus()
      try NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: contactURL)
    }
    try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("render-comparison.json"))
    print("Measured \(results.count) actual native PDF / Quick Look pairs. Differences are evidence, not automatic approval.")
  }

  static func bitmap(_ url: URL) -> NSBitmapImageRep? {
    guard let image = NSImage(contentsOf: url) else { return nil }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 960, pixelsHigh: 540, bitsPerSample: 8, samplesPerPixel: 4,
      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 960, height: 540).fill()
    image.draw(in: NSRect(x: 0, y: 0, width: 960, height: 540))
    NSGraphicsContext.restoreGraphicsState()
    return rep
  }
}
