import Foundation

@main
struct PersonalizationChecks {
  static func main() throws {
    precondition(OccupationCatalog.categories.count == 16)
    precondition(OccupationCatalog.occupations.count == 116)
    let occupations = OccupationCatalog.occupations
    precondition(Set(occupations.map(\.id)).count == occupations.count)
    let templateIDs = Set(SummaryTemplateCatalog.market.map(\.id))
      .union(SummaryTemplateChoice.builtInChoices.map(\.id))
    precondition(occupations.allSatisfy { Set($0.recommendedTemplateIDs).isSubset(of: templateIDs) })
    for (occupation, expected) in [
      ("occupation.beauty.hairstylist", "work.customer-chart"),
      ("occupation.care.caregiver", "work.shift-handover"),
      ("occupation.construction.electrician", "work.daily")
    ] {
      var profile = UserOccupationProfile()
      profile.select(occupation, isSelected: true)
      precondition(OccupationCatalog.recommendedIDs(for: profile).first == expected)
      profile.select(occupation, isSelected: true)
      precondition(profile.selectedOccupationIDs.count == 1)
      let restored = try JSONDecoder().decode(UserOccupationProfile.self, from: JSONEncoder().encode(profile))
      precondition(restored == profile)
    }
    precondition(OccupationCatalog.matching("美容師").count == 1)
    var profile = UserOccupationProfile()
    profile.select("occupation.beauty.hairstylist", isSelected: true)
    profile.select("occupation.care.caregiver", isSelected: true)
    profile.primaryOccupationID = "occupation.care.caregiver"
    let recommended = OccupationCatalog.recommendedIDs(for: profile)
    precondition(recommended.first == "work.shift-handover")
    precondition(Set(recommended).count == recommended.count)
    profile.select("occupation.care.caregiver", isSelected: false)
    precondition(profile.primaryOccupationID == "occupation.beauty.hairstylist")
    let legacy = Data(#"{"id":"custom.old","title":"旧形式","detail":"説明","symbol":"doc.text","lead":"要約"}"#.utf8)
    let template = try JSONDecoder().decode(SummaryMarketTemplate.self, from: legacy)
    precondition(template.id == "custom.old" && template.sensitivityClassification == .general)
    precondition(template.supportedSummaryLengths == SummaryLength.allCases)
    let suite = "Memora.PersonalizationChecks.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    precondition(SummaryPreferences.initial(defaults: defaults).method == .automatic)
    defaults.set("market.regular", forKey: "memora.summary.defaultTemplate")
    precondition(SummaryPreferences.initial(defaults: defaults).method == .fixed)
    print("PersonalizationChecks: passed (16 categories, 116 occupations, recommendations, migration)")
  }
}
