import Foundation

struct AIPluginIcon {
  var pluginID: String
  var icon: MemoraIcon
  var accessibilityLabel: String

  // Brand identity comes from the registered service, never an untrusted display name.
  var brandAssetName: String? {
    if pluginID.hasPrefix("mcp:") { return "service.mcp" }
    guard pluginID.hasPrefix("service:") else { return nil }
    let service = String(pluginID.dropFirst(8))
    return ["gmail", "drive", "notion", "github", "linear", "mcp"].contains(service) ? "service." + service : nil
  }

  static func resolve(pluginID: String, name: String, iconIdentifier: String? = nil) -> Self {
    let services: [String: MemoraIcon] = ["gmail": .envelope, "notion": .notionLogo, "calendar": .calendar,
      "drive": .externaldrive, "github": .chevronLeftForwardslashChevronRight, "mcp": .plugsConnected]
    let symbol: MemoraIcon
    if let iconIdentifier, let stored = MemoraIcon(rawValue: iconIdentifier) { symbol = stored }
    else if pluginID.hasPrefix("service:") { symbol = services[String(pluginID.dropFirst(8))] ?? .plugsConnected }
    else if pluginID.hasPrefix("template:") { symbol = .docOnDoc }
    else if pluginID.hasPrefix("record:") || pluginID.hasPrefix("source:") { symbol = .docText }
    else if pluginID.hasPrefix("person:") { symbol = .person }
    else if pluginID.hasPrefix("project:") { symbol = .folder }
    else if pluginID.hasPrefix("skill:") { symbol = .docRichtext }
    else if pluginID.contains("deep_research") || pluginID.contains("search_web") { symbol = .magnifyingglass }
    else if pluginID.hasPrefix("tool:") { symbol = .docText }
    else { symbol = .plugsConnected }
    return Self(pluginID: pluginID, icon: symbol, accessibilityLabel: name)
  }
}
