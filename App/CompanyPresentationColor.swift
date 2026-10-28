import Foundation

enum CompanyPresentationColor {
  static func resolve(_ role: String, master: CompanyPresentationProfile.Master, lightened: Bool = false) throws -> String {
    let defaults = ["bg1": "lt1", "bg2": "lt2", "tx1": "dk1", "tx2": "dk2"]
    let slot = master.colorMap[role] ?? defaults[role] ?? role
    guard let hex = master.theme?.colors[slot], isHex(hex) else { throw CompanyPresentationPreview.Failure.unsupported }
    return lightened ? try tint(hex, multiplier: 0.2, offset: 0.8) : hex.uppercased()
  }

  static func isHex(_ value: String) -> Bool {
    value.utf8.count == 6 && value.unicodeScalars.allSatisfy { (48...57).contains($0.value) || (65...70).contains($0.value) || (97...102).contains($0.value) }
  }

  /// DrawingML lumMod/lumOff operate on HSL lightness, not individual RGB channels.
  static func tint(_ hex: String, multiplier: Double, offset: Double) throws -> String {
    guard isHex(hex), let rgb = UInt32(hex, radix: 16) else { throw CompanyPresentationPreview.Failure.unsupported }
    let values = [Double((rgb >> 16) & 255), Double((rgb >> 8) & 255), Double(rgb & 255)].map { $0 / 255 }
    let high = values.max()!, low = values.min()!, lightness = (high + low) / 2
    let delta = high - low
    let saturation = delta == 0 ? 0 : delta / (1 - abs(2 * lightness - 1))
    let newLightness = min(1, max(0, lightness * multiplier + offset))
    let chroma = (1 - abs(2 * newLightness - 1)) * saturation
    let minimum = newLightness - chroma / 2
    let output = values.map { channel in
      let component = delta == 0 ? newLightness : minimum + (channel - low) / delta * chroma
      return Int((min(1, max(0, component)) * 255).rounded())
    }
    return String(format: "%02X%02X%02X", output[0], output[1], output[2])
  }
}
