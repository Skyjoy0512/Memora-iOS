import Foundation

enum CompanyPresentationColor {
  private static let drawing: Set<String> = ["http://schemas.openxmlformats.org/drawingml/2006/main"]

  static func resolve(_ role: String, master: CompanyPresentationProfile.Master, lightened: Bool = false) throws -> String {
    let defaults = ["bg1": "lt1", "bg2": "lt2", "tx1": "dk1", "tx2": "dk2"]
    let slot = master.colorMap[role] ?? defaults[role] ?? role
    guard let hex = master.theme?.colors[slot], isHex(hex) else { throw CompanyPresentationPreview.Failure.unsupported }
    return lightened ? try tint(hex, multiplier: 0.2, offset: 0.8) : hex.uppercased()
  }

  static func isHex(_ value: String) -> Bool {
    value.utf8.count == 6 && value.unicodeScalars.allSatisfy { (48...57).contains($0.value) || (65...70).contains($0.value) || (97...102).contains($0.value) }
  }

  static func decorationFill(_ fill: Int, in xml: OfficeXMLDocument, master: CompanyPresentationProfile.Master) throws -> String {
    guard xml.matches(fill, "solidFill", namespaces: drawing), xml.nodes[fill].attributes.isEmpty,
          xml.nodes[fill].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          xml.nodes[fill].children.count == 1 else { throw CompanyPresentationPreview.Failure.unsupported }
    let color = xml.nodes[xml.nodes[fill].children[0]]
    guard drawing.contains(color.namespace), color.attributes.count == 1, let value = color.attributes["val"],
          color.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          color.children.count <= 4 else { throw CompanyPresentationPreview.Failure.unsupported }
    let hex: String
    if color.name == "srgbClr", isHex(value) { hex = value.uppercased() }
    else if color.name == "schemeClr" { hex = try resolve(value, master: master) }
    else { throw CompanyPresentationPreview.Failure.unsupported }
    var operations: [(multiplier: Double, offset: Double)] = []
    for index in color.children {
      let step = xml.nodes[index]
      guard drawing.contains(step.namespace), ["lumMod", "lumOff"].contains(step.name),
            step.children.isEmpty, step.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            step.attributes.count == 1, let raw = step.attributes["val"], (1...6).contains(raw.utf8.count),
            raw.utf8.allSatisfy({ (48...57).contains($0) }), let percentage = Int(raw), percentage <= 100_000 else {
        throw CompanyPresentationPreview.Failure.unsupported
      }
      let amount = Double(percentage) / 100_000
      operations.append(step.name == "lumMod" ? (amount, 0) : (1, amount))
    }
    if operations.isEmpty { return hex }
    return try transformed(hex, operations: operations)
  }

  /// DrawingML lumMod/lumOff operate on HSL lightness, not individual RGB channels.
  static func tint(_ hex: String, multiplier: Double, offset: Double) throws -> String {
    guard multiplier.isFinite, offset.isFinite, (0...1).contains(multiplier), (0...1).contains(offset) else {
      throw CompanyPresentationPreview.Failure.unsupported
    }
    return try transformed(hex, operations: [(multiplier, offset)])
  }

  private static func transformed(_ hex: String, operations: [(multiplier: Double, offset: Double)]) throws -> String {
    guard isHex(hex), let rgb = UInt32(hex, radix: 16) else { throw CompanyPresentationPreview.Failure.unsupported }
    let values = [Double((rgb >> 16) & 255), Double((rgb >> 8) & 255), Double(rgb & 255)].map { $0 / 255 }
    let high = values.max()!, low = values.min()!, lightness = (high + low) / 2
    let delta = high - low
    let saturation = delta == 0 ? 0 : delta / (1 - abs(2 * lightness - 1))
    // Preserve XML order and clamp each step without quantizing back to RGB between transforms.
    let newLightness = operations.reduce(lightness) { min(1, max(0, $0 * $1.multiplier + $1.offset)) }
    let chroma = (1 - abs(2 * newLightness - 1)) * saturation
    let minimum = newLightness - chroma / 2
    let output = values.map { channel in
      let component = delta == 0 ? newLightness : minimum + (channel - low) / delta * chroma
      return Int((min(1, max(0, component)) * 255).rounded())
    }
    return String(format: "%02X%02X%02X", output[0], output[1], output[2])
  }
}
