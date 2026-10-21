import Foundation

@main
struct SkillEditingPolishChecks {
  static func main() {
    var skill = MemoraSkill.draft(instructions: "  Confirm the goal, then review the result.  ")
    let empty = SkillEditorInput(skill: skill, keywords: "")
    precondition(empty.validationMessage?.contains("スキル名") == true)
    skill.name = "  Meeting Brief  "
    precondition(SkillEditorInput(skill: skill, keywords: "").validationMessage?.contains("いつ使うか") == true)
    skill.summary = "  Prepare a meeting brief.  "
    let input = SkillEditorInput(skill: skill, keywords: " 会議、企画，MAIL, mail,会議, ")
    let normalized = input.normalizedSkill
    precondition(input.validationMessage == nil)
    precondition(normalized.name == "Meeting Brief" && normalized.summary == "Prepare a meeting brief.")
    precondition(normalized.instructions == "Confirm the goal, then review the result.")
    precondition(normalized.keywords == ["会議", "企画", "MAIL"])
    precondition(normalized.id == skill.id && normalized.toolNames == skill.toolNames && normalized.scopes == skill.scopes)
    precondition(input.hasChanges(from: skill))
    precondition(!SkillEditorInput(skill: normalized, keywords: "会議、企画，MAIL").hasChanges(from: normalized))
    var invalid = normalized
    invalid.name = String(repeating: "a", count: 81)
    precondition(SkillEditorInput(skill: invalid, keywords: "").validationMessage?.contains("80文字") == true)
    invalid = normalized; invalid.summary = String(repeating: "a", count: 401)
    precondition(SkillEditorInput(skill: invalid, keywords: "").validationMessage?.contains("400文字") == true)
    invalid = normalized; invalid.instructions = String(repeating: "手", count: 6_001)
    let longInput = SkillEditorInput(skill: invalid, keywords: "")
    precondition(longInput.validationMessage?.contains("6,000文字") == true && longInput.normalizedSkill.instructions.count == 6_001)
    precondition(SkillEditorInput(skill: normalized, keywords: "1,2,3,4,5,6,7,8,9").validationMessage?.contains("8個") == true)
    precondition(SkillEditorInput(skill: normalized, keywords: String(repeating: "a", count: 41)).validationMessage?.contains("40文字") == true)
    invalid = normalized; invalid.instructions = " \n "
    precondition(SkillEditorInput(skill: invalid, keywords: "").validationMessage?.contains("作業手順") == true)
    invalid = normalized; invalid.summary = "first\nsecond"
    precondition(SkillEditorInput(skill: invalid, keywords: "").validationMessage?.contains("1行") == true)
    precondition(ToolsCatalogSearch.matches("  Google  Drive ", fields: ["Google Drive", "資料"]))
    precondition(ToolsCatalogSearch.matches("ｇｏｏｇｌｅ", fields: ["Google Drive"]))
    precondition(ToolsCatalogSearch.matches("会議 review", fields: ["会議の準備", "Review notes"]))
    precondition(ToolsCatalogSearch.matches("  ", fields: []))
    precondition(!ToolsCatalogSearch.matches("unknown", fields: ["Google Drive"]))
    print("SkillEditingPolishChecks: passed (required fields, limits, no truncation, Japanese separators, deduplication, change detection, identity/scope preservation, catalog matching)")
  }
}
