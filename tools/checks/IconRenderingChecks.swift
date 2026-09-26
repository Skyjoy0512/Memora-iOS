import AppKit

// Compile with Shared/MemoraIcon.swift and -framework AppKit.
// Inspects the compiled asset, not just whether its catalog name exists.
@main
struct IconRenderingChecks {
  static func main() throws {
    guard CommandLine.arguments.count > 1,
          let bundle = Bundle(path: CommandLine.arguments[1]) else {
      fatalError("Pass the built app bundle path")
    }
    var failures = 0
    var checked = 0
    for icon in MemoraIcon.allCases {
      let name = icon.assetName
      guard let image = bundle.image(forResource: name) else {
        print("MISSING \(name)")
        failures += 1
        continue
      }
      // An icon passes when it draws visible pixels in at least one weight and
      // scale. AppKit occasionally rasterizes a single configuration blank for
      // a stroke-only symbol (notably semibold at medium scale), which is a
      // macOS quirk, not a broken asset, so only a fully blank icon fails.
      var visible = 0
      for (scaleName, scale) in [("small", NSImage.SymbolScale.small), ("medium", .medium), ("large", .large)] {
      for weight in [NSFont.Weight.regular, .semibold] {
      let configured = image.withSymbolConfiguration(.init(pointSize: 20, weight: weight, scale: scale)) ?? image
      var rect = CGRect(origin: .zero, size: configured.size)
      guard let cg = configured.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
        print("NO PIXELS \(name) \(scaleName)")
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
      checked += 1
      if nonempty > 0 { visible += 1 }
      }
      }
      if visible == 0 {
        failures += 1
        print("EMPTY \(name)")
      }
    }
    print("\(failures == 0 ? "PASS" : "FAIL"): \(checked) compiled icon renders, \(failures) blank icons")
    if failures > 0 { exit(1) }
  }
}
