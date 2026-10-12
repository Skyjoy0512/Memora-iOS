import Foundation

enum ShareInboxConfiguration {
  static var root: URL? {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "MemoraShareAppGroup") as? String,
          let bundleID = Bundle.main.bundleIdentifier else { return nil }
    let hostID = bundleID.hasSuffix(".share-extension") ? String(bundleID.dropLast(".share-extension".count)) : bundleID
    guard !hostID.hasPrefix("app.bitrig.new."), group == "group." + hostID else { return nil }
    return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
      .appendingPathComponent("ShareInbox", isDirectory: true)
  }
}
