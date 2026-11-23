import Foundation

enum ShareInboxConfiguration {
  static var root: URL? {
    guard let configuredGroup = Bundle.main.object(forInfoDictionaryKey: "MemoraShareAppGroup") as? String else { return nil }
    #if DEBUG
    let group = configuredGroup + ".debug"
    #else
    let group = configuredGroup
    #endif
    return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
      .appendingPathComponent("ShareInbox", isDirectory: true)
  }
}
