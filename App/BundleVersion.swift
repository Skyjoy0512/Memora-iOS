import Foundation

extension Bundle {
  /// The marketing version with its build, read from the bundle so it always
  /// matches what was shipped.
  var appVersion: String {
    let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    guard let build = infoDictionary?["CFBundleVersion"] as? String, !build.isEmpty else {
      return version
    }
    return "\(version) (\(build))"
  }
}
