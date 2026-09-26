import AppKit

// Inspects the compiled asset, not just whether its catalog name exists.
@main
struct IconRenderingChecks {
  static func main() throws {
    guard CommandLine.arguments.count > 1,
          let bundle = Bundle(path: CommandLine.arguments[1]) else {
      fatalError("Pass the built app bundle path")
    }
    for name in ["memora.gearshape", "memora.crown.fill", "memora.plus", "memora.folder"] {
      guard let image = bundle.image(forResource: name) else {
        print("MISSING \(name)")
        continue
      }
      var rect = CGRect(origin: .zero, size: image.size)
      guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
        print("NO PIXELS \(name)")
        continue
      }
      let width = cg.width
      let height = cg.height
      var pixels = [UInt8](repeating: 0, count: width * height * 4)
      let nonempty = pixels.withUnsafeMutableBytes { buffer -> Int in
        let context = CGContext(data: buffer.baseAddress, width: width, height: height,
          bitsPerComponent: 8, bytesPerRow: width * 4,
          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = buffer.bindMemory(to: UInt8.self)
        return stride(from: 3, to: bytes.count, by: 4).filter { bytes[$0] > 16 }.count
      }
      print("\(name): \(width)x\(height), visible pixels=\(nonempty)")
    }
  }
}
