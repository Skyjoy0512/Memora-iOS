import Foundation

/// A rough token count used only when the provider gives none. CJK characters
/// count as one token each; runs of other letters at about three characters per
/// token. This is a budgeting estimate, never a billing figure.
enum TokenEstimate {
  static func tokens(_ text: String) -> Int {
    var tokens = 0
    var asciiRun = 0
    func flush() {
      if asciiRun > 0 { tokens += (asciiRun + 2) / 3 }
      asciiRun = 0
    }
    for scalar in text.unicodeScalars {
      switch scalar.value {
      case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xFF00...0xFFEF:
        flush()
        tokens += 1
      case 0x20, 0x09, 0x0A, 0x0D:
        flush()
        tokens += 1
      default:
        asciiRun += 1
      }
    }
    flush()
    return tokens
  }
}
