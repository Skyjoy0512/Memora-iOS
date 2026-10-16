import Foundation

@main struct PluginIconChecks {
  static func main() throws {
    let names = ["gmail", "notion", "calendar", "drive", "github", "mcp"]
    let icons = names.map { AIPluginIcon.resolve(pluginID: "service:" + $0, name: $0).systemSymbol }
    precondition(Set(icons).count == names.count)
    precondition(AIPluginIcon.resolve(pluginID: "record:fixture", name: "資料").systemSymbol == .docText)
    precondition(AIPluginIcon.resolve(pluginID: "skill:old", name: "旧スキル", iconIdentifier: "unknown").systemSymbol == .docRichtext)
    let builtin = MemoraSkill.bundled
    precondition(builtin.count == 15 && Set(builtin.map(\.id)).count == 15)
    precondition(builtin.allSatisfy { !$0.toolNames.isEmpty })
    for skill in builtin.suffix(12) {
      precondition(skill.version == 1 && MemoraIcon(rawValue: skill.iconIdentifier!) != nil)
      let parsed = try MemoraSkillMarkdown.parse(skill.skillMarkdown, allowedTools: Set(skill.toolNames))
      precondition(parsed.iconIdentifier == skill.iconIdentifier && parsed.version == 1)
    }
    print("PluginIconChecks: passed (distinct service symbols, fallback, 15 skills, stable icon/version roundtrip)")
  }
}
