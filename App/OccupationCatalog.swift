import Foundation

enum OccupationCatalog {
  private struct Catalog: Decodable {
    var categories: [OccupationCategory]
    var occupations: [Occupation]
    var useCases: [SummaryUseCase]
  }
  private static let data: Catalog? = {
    guard let url = Bundle.main.url(forResource: "OccupationCatalog", withExtension: "json"),
          let bytes = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(Catalog.self, from: bytes)
  }()
  static var categories: [OccupationCategory] { (data?.categories ?? []).sorted { $0.sortOrder < $1.sortOrder } }
  static var occupations: [Occupation] { data?.occupations ?? [] }
  static var useCases: [SummaryUseCase] { data?.useCases ?? [] }
  static func occupation(_ id: String) -> Occupation? { occupations.first { $0.id == id } }

  static func recommendedIDs(for profile: UserOccupationProfile) -> [String] {
    var seen: Set<String> = []
    return profile.orderedIDs.compactMap(occupation).flatMap(\.recommendedTemplateIDs)
      .filter { seen.insert($0).inserted }
  }

  static func matching(_ query: String) -> [Occupation] {
    let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
    return occupations.filter { occupation in
      let text = occupation.title + " " + occupation.description
      return terms.allSatisfy { text.localizedStandardContains($0) }
    }
  }
}
