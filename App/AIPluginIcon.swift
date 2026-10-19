import Foundation

struct AIPluginIcon {
  enum Kind { case systemSymbol, asset }
  var pluginID: String
  var kind: Kind = .systemSymbol
  var systemSymbol: MemoraIcon
  var assetName: String?
  var fallbackIcon: MemoraIcon = .plugsConnected
  var accessibilityLabel: String

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
    return Self(pluginID: pluginID, systemSymbol: symbol, accessibilityLabel: name)
  }
}
