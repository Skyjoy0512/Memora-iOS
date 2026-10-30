import Foundation

@main struct PluginIconChecks {
  static func main() throws {
    let names = ["gmail", "notion", "calendar", "drive", "github", "mcp"]
    let icons = names.map { AIPluginIcon.resolve(pluginID: "service:" + $0, name: $0).icon }
    precondition(Set(icons).count == names.count)
    precondition(AIPluginIcon.resolve(pluginID: "service:calendar", name: "カレンダー").icon == .calendar)
    precondition(AIPluginIcon.resolve(pluginID: "record:fixture", name: "資料").icon == .docText)
    precondition(AIPluginIcon.resolve(pluginID: "skill:old", name: "旧スキル", iconIdentifier: "unknown").icon == .docRichtext)
    let builtin = MemoraSkill.bundled
    let expectedIDs: Set<String> = ["project-reading", "journal-review", "project-organize", "travel-plan",
      "proposal", "executive-report", "meeting-report", "business-plan", "powerpoint", "word-document",
      "company-template", "periodic-report", "research-report", "email-draft", "meeting-followup", "person-conversation"]
    precondition(builtin.count == expectedIDs.count && Set(builtin.map(\.id)) == expectedIDs)
    precondition(builtin.allSatisfy { !$0.toolNames.isEmpty })
    for skill in builtin.suffix(12) {
      precondition(skill.version == 1 && MemoraIcon(rawValue: skill.iconIdentifier!) != nil)
      let parsed = try MemoraSkillMarkdown.parse(skill.skillMarkdown, allowedTools: Set(skill.toolNames))
      precondition(parsed.iconIdentifier == skill.iconIdentifier && parsed.version == 1)
    }
    let skill = builtin.first { $0.id == "powerpoint" }!
    precondition(skill.unavailabilityReason(enabled: true, availableTools: Set(skill.toolNames), onDeviceTools: ["read_record"]) != nil)
    precondition(skill.unavailabilityReason(enabled: false, availableTools: Set(skill.toolNames), onDeviceTools: nil) != nil)
    precondition(skill.unavailabilityReason(enabled: true, availableTools: [], onDeviceTools: nil) != nil)
    precondition(skill.unavailabilityReason(enabled: true, availableTools: Set(skill.toolNames), onDeviceTools: nil) == nil)
    print("PluginIconChecks: passed (Lucide service glyphs, calendar glyph, legacy ID fallback, 16 distinct skills, stable icon/version roundtrip)")
  }
}
