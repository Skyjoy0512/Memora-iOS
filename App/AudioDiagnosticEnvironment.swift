import Foundation

struct AudioDiagnosticEnvironment: Codable, Sendable {
  var hardware: String
  var osVersion: String
  var build: String
  var isSimulator: Bool

  static var current: Self {
    var system = utsname()
    uname(&system)
    let hardware = withUnsafeBytes(of: &system.machine) { bytes in
      String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
    let os = ProcessInfo.processInfo.operatingSystemVersion
    #if targetEnvironment(simulator)
    let simulated = true
    #else
    let simulated = false
    #endif
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "host"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    return Self(hardware: safe(hardware), osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
      build: safe("\(version)-\(build)"), isSimulator: simulated)
  }

  var isValid: Bool {
    [hardware, osVersion, build].allSatisfy { !$0.isEmpty && $0 == Self.safe($0) }
  }

  private static func safe(_ value: String) -> String {
    String(value.filter { $0.isASCII && ($0.isLetter || $0.isNumber || "._,-".contains($0)) }.prefix(64))
  }
}
