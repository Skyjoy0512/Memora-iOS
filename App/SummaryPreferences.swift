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
  var processingMode: SummaryProcessingMode = .balanced

  static func loadOrMigrate(defaults: UserDefaults = .standard) -> Self {
    let key = "memora.summaryPreferences"
    if let saved = defaults.data(forKey: key) {
      return (try? JSONDecoder().decode(Self.self, from: saved)) ?? initial(defaults: defaults)
    }
    let preferences = initial(defaults: defaults)
    if let encoded = try? JSONEncoder().encode(preferences) { defaults.set(encoded, forKey: key) }
    return preferences
  }

  var orderingInstruction: String {
    displayOrder == .chronological
      ? "見出しの順序は指定された形式を守り、各見出しの中は発言・出来事の時系列で整理する。"
      : "見出しの順序は指定された形式を守り、各見出しの中は結論・注意点・約束を先に整理する。"
  }

  static func initial(defaults: UserDefaults = .standard) -> Self {
    let existing = defaults.bool(forKey: "hasSeenMemoraWelcome")
      || defaults.string(forKey: "memora.summary.defaultTemplate") != nil
    return Self(method: existing ? .fixed : .automatic)
  }
}

extension SummaryPreferences {
  private enum CodingKeys: String, CodingKey { case method, length, displayOrder, processingMode }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    method = try values.decodeIfPresent(Method.self, forKey: .method) ?? .automatic
    length = try values.decodeIfPresent(SummaryLength.self, forKey: .length) ?? .standard
    displayOrder = try values.decodeIfPresent(DisplayOrder.self, forKey: .displayOrder) ?? .importance
    processingMode = try values.decodeIfPresent(SummaryProcessingMode.self, forKey: .processingMode) ?? .balanced
  }
}
