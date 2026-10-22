@main
struct SettingsNavigationChecks {
  static func main() {
    let categories = SettingsCategory.allCases
    precondition(Set(categories) == [.account, .workspace, .plan, .recording, .ai, .journal,
      .integrations, .appearance, .privacy, .data, .about, .diagnostics])
    precondition(Set(categories.map(\.id)).count == categories.count)
    precondition(Set(categories.map(\.title)).count == categories.count)
    precondition(SettingsCategory.groups.count == 4)
    precondition(Set(categories.map(\.group)) == Set(SettingsCategory.groups))
    precondition(categories.filter { $0.group == "アプリ" }.count == 5)
    precondition(SettingsCategory.integrations.title == "連携")
    precondition(SettingsCategory.ai.title == "AIと要約")
    precondition(categories.allSatisfy { !$0.icon.systemName.isEmpty })
    precondition(MemoraIconMetrics.glyph == 20)
    precondition(MemoraIconMetrics.slot >= MemoraIconMetrics.glyph)
    precondition(MemoraIconMetrics.touchTarget >= 44)
    print("SettingsNavigationChecks passed: 12 distinct topics including workspace, four groups, common icon and touch metrics")
  }
}
