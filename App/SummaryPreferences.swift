import Foundation

struct SummaryPreferences: Codable, Equatable {
  enum Method: String, Codable, CaseIterable {
    case automatic, fixed
    var title: String { self == .automatic ? "AIにおまかせ" : "既定のテンプレートを使用" }
  }
  enum DisplayOrder: String, Codable, CaseIterable {
    case importance, chronological
    var title: String { self == .importance ? "重要情報を先に" : "時系列を重視" }
  }
  var method: Method = .automatic
  var length: SummaryLength = .standard
  var displayOrder: DisplayOrder = .importance

  static func initial(defaults: UserDefaults = .standard) -> Self {
    let existing = defaults.bool(forKey: "hasSeenMemoraWelcome")
      || defaults.string(forKey: "memora.summary.defaultTemplate") != nil
    return Self(method: existing ? .fixed : .automatic)
  }
}
