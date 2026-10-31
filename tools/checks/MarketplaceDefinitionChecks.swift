import Foundation

@main struct MarketplaceDefinitionChecks {
  static func main() throws {
    let tools = Set(["search_records","read_record","list_projects","list_tasks","review_period","update_tasks","read_person","create_document","create_slides","add_tasks","create_project","move_records_to_project","add_journal_memo","read_calendar","create_calendar_event","draft_email","save_to_notion","save_memory","search_email","read_email","ask_user","delegate_research","search_web","deep_research"])
    for skill in MemoraSkill.bundled {
      let original = MarketplaceDefinition(skill: skill)
      let decoded = try MarketplaceDefinition.read(original.shareText, allowedTools: tools)
      precondition(decoded.skill?.id.hasPrefix("custom-") == true)
      precondition(decoded.skill?.instructions == skill.instructions)
      precondition(decoded.skill?.toolNames == skill.toolNames, "legacy tools must survive sharing: \(skill.id)")
      precondition(decoded.skill?.id != skill.id)
    }
    for template in SummaryTemplateCatalog.market {
      let decoded = try MarketplaceDefinition.read(MarketplaceDefinition(template: template).shareText, allowedTools: tools)
      precondition(decoded.template?.sections == template.sections)
      precondition(decoded.template?.focus == template.focus)
      precondition(decoded.template?.includesActions == template.includesActions)
      precondition(decoded.template?.isCustom == true)
    }
    var forbidden = MemoraSkill.draft(instructions: "run")
    forbidden.name = "test"; forbidden.summary = "test"; forbidden.declaredToolNames = ["shell_exec"]
    do { _ = try MarketplaceDefinition(skill: forbidden).validated(allowedTools: tools); preconditionFailure("unknown tool accepted") }
    catch CommunityError.invalidContent {}
    do { _ = try MarketplaceDefinition.read(String(repeating: "a", count: 32769), allowedTools: tools); preconditionFailure("oversize accepted") }
    catch CommunityError.invalidContent {}
    let legacy = try MarketplaceDefinition.read(MemoraSkill.bundled[0].skillMarkdown, allowedTools: tools)
    precondition(legacy.skill?.name == MemoraSkill.bundled[0].name)
    if let path = ProcessInfo.processInfo.environment["MEMORA_MARKETPLACE_FIXTURE_PATH"] {
      let definitions = MemoraSkill.bundled.map(MarketplaceDefinition.init(skill:)) + SummaryTemplateCatalog.market.map(MarketplaceDefinition.init(template:))
      try JSONEncoder().encode(definitions).write(to: URL(fileURLWithPath: path))
    }
    print("Marketplace definitions: real catalog round trips, legacy tool preservation, unknown tool rejection, bounded imports passed")
  }
}
