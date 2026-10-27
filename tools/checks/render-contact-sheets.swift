import AppKit

/// Contact sheets contain renderer output, never a substitute for rendering a deck.
@main enum RenderContactSheets {
  static func main() throws {
    let input = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let files = try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    for offset in stride(from: 0, to: files.count, by: 15) {
      let page = NSImage(size: NSSize(width: 1472, height: 1506))
      page.lockFocus()
      NSColor(white: 0.92, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 1472, height: 1506).fill()
      for (index, file) in files.dropFirst(offset).prefix(15).enumerated() {
        guard let image = NSImage(contentsOf: file) else { throw CocoaError(.fileReadCorruptFile) }
        let x = 8 + (index % 3) * 488, y = 1506 - 8 - (index / 3 + 1) * 298
        image.draw(in: NSRect(x: x, y: y + 22, width: 480, height: 270))
        (String(file.lastPathComponent.prefix(3)) as NSString).draw(at: NSPoint(x: x, y: y + 2),
          withAttributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.black])
      }
      page.unlockFocus()
      guard let tiff = page.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
            let bytes = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
      try bytes.write(to: output.appendingPathComponent("sheet-\(offset / 15 + 1).png"), options: .atomic)
    }
    print("Contact sheets: \(files.count) rendered images")
  }
}
