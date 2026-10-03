import Foundation

/// Japanese phone numbers as people type them (090-1234-5678) and as the
/// phone network wants them (+819012345678).
enum PhoneNumberFormat {
  /// The number in E.164, or nil when it is not a plausible number.
  static func e164(_ input: String, defaultCountryCode: String = "81") -> String? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let digits = trimmed.filter(\.isNumber)
    if trimmed.hasPrefix("+") {
      return (8...15).contains(digits.count) ? "+" + digits : nil
    }
    guard digits.hasPrefix("0"), (10...11).contains(digits.count) else { return nil }
    return "+\(defaultCountryCode)" + digits.dropFirst()
  }

  /// A number grouped for reading: +81 90-1234-5678.
  static func display(_ e164: String) -> String {
    guard e164.hasPrefix("+81") else { return e164 }
    let national = String(e164.dropFirst(3))
    let groups: [Int] = national.count == 10 ? [2, 4, 4] : national.count == 9 ? [1, 4, 4] : [national.count]
    var parts: [String] = []
    var index = national.startIndex
    for length in groups {
      let end = national.index(index, offsetBy: length, limitedBy: national.endIndex) ?? national.endIndex
      parts.append(String(national[index..<end]))
      index = end
    }
    return "+81 " + parts.joined(separator: "-")
  }
}
