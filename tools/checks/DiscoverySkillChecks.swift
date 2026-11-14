import Foundation

@main
struct DiscoverySkillChecks {
  static func main() throws {
    let candidates: [SemanticToolDiscovery.Candidate] = [
      .init(id: "z-calendar", name: "calendar events", summary: "upcoming calendar", schemaBytes: 100),
      .init(id: "b-mail", name: "search_email", summary: "gmail mail search", schemaBytes: 200),
      .init(id: "a-disabled", name: "search_email", summary: "gmail", schemaBytes: 1, isEnabled: false),
      .init(id: "c-offline", name: "search_email", summary: "gmail", schemaBytes: 1, isAvailable: false),
      .init(id: "d-large", name: "search_email", summary: "gmail", schemaBytes: 25_000)
    ]
    let mail = SemanticToolDiscovery.select(candidates, request: "昨日のメールを確認", explicit: false)
    precondition(mail == ["b-mail"])
    precondition(SemanticToolDiscovery.select(candidates.reversed(), request: "昨日のメールを確認", explicit: false) == mail)
    precondition(SemanticToolDiscovery.select(candidates, request: "来週の予定", explicit: false) == ["z-calendar"])
    precondition(SemanticToolDiscovery.select(candidates, request: "こんにちは", explicit: false).isEmpty)
    precondition(SemanticToolDiscovery.select(candidates, request: "こんにちは", explicit: true, limit: 1) == ["b-mail"])
    precondition(SemanticToolDiscovery.select(candidates, request: "メール", explicit: false, byteLimit: 100).isEmpty)
    let source = "---\nname: 会議フォロー\ndescription: 決定とタスクを確認\ntools: list_tasks, read_record\nkeywords: 会議, フォロー\npermissions: memora.read\n---\n\n実際の記録を読み、未完了の作業を整理する。"
    let known: Set<String> = ["list_tasks", "read_record"]
    let skill = try MemoraSkillMarkdown.parse(source, allowedTools: known)
    precondition(skill.toolNames == ["list_tasks", "read_record"] && skill.declaredPermissions == ["memora.read"])
    let roundTrip = try JSONDecoder().decode(MemoraSkill.self, from: JSONEncoder().encode(skill))
    precondition(roundTrip.id == skill.id && roundTrip.instructions == skill.instructions)
    let imported = try MemoraSkillMarkdown.parse(skill.skillMarkdown, allowedTools: known)
    precondition(imported.id != skill.id && imported.name == skill.name && imported.toolNames == skill.toolNames)
    precondition(skill.category == nil && skill.examplePrompts == nil && skill.outputDescription == nil)
    let legacyJSON = "{\"id\":\"legacy\",\"name\":\"旧スキル\",\"summary\":\"用途\",\"instructions\":\"手順\",\"keywords\":[]}"
    let legacySkill = try JSONDecoder().decode(MemoraSkill.self, from: Data(legacyJSON.utf8))
    precondition(legacySkill.category == nil && legacySkill.examplePrompts == nil)
    precondition(MemoraSkill.bundled.count == 48)
    for original in MemoraSkill.breadthSkills {
      let decoded = try MemoraSkillMarkdown.parse(original.skillMarkdown, allowedTools: ["search_records", "read_record"])
      precondition(decoded.category == original.category && decoded.examplePrompts == original.examplePrompts && decoded.outputDescription == original.outputDescription)
      precondition(Set(decoded.toolNames) == ["search_records", "read_record"])
      precondition(MemoraSkill.automaticSelection(for: original.name, disabled: []).first?.id == original.id)
    }
    let context = MemoraSkill.context(for: "会議のフォロー", disabled: [], budget: 300, catalog: [skill])
    precondition(context.contains("未信頼") && context.contains("実際の記録"))
    precondition(MemoraSkill.context(for: "会議", disabled: [skill.id], budget: 300, catalog: [skill]).isEmpty)
    var reusable = MemoraSkill.draft(instructions: "目的と読者を確認し、決定事項・未確認事項・次の作業を分けてまとめる。")
    reusable.name = "議事録レビュー"
    reusable.summary = "会議の記録を確認するときに使う"
    precondition(MemoraSkillMarkdown.valid(reusable))
    precondition(reusable.toolNames.isEmpty && reusable.cost == .model)
    precondition(MemoraSkill.automaticSelection(for: "議事録レビューで整理して", disabled: [], catalog: [reusable]).map(\.id) == [reusable.id])
    precondition(MemoraSkill.automaticSelection(for: "議事録レビュー", disabled: [reusable.id], catalog: [reusable]).isEmpty)
    precondition(MemoraSkill.automaticSelection(for: "関係のない質問", disabled: [], catalog: [reusable]).isEmpty)
    precondition(MemoraSkill.automaticSelection(for: "  ", disabled: [], catalog: [reusable]).isEmpty)
    let priority = MemoraSkill.automaticSelection(for: "会議のフォローを議事録レビューで", disabled: [], catalog: [skill, reusable])
    precondition(priority.first?.id == reusable.id && priority.count == 2)
    let longDraft = MemoraSkill.draft(instructions: String(repeating: "手", count: 6_001))
    precondition(longDraft.instructions.count == 6_001 && !MemoraSkillMarkdown.valid(longDraft))
    var completeProcedure = reusable
    completeProcedure.instructions = String(repeating: "手", count: 5_990) + "最終確認を省略しない"
    precondition(MemoraSkill.guidance([completeProcedure, skill], budget: 14_000).contains("最終確認を省略しない"))
    for invalid in [
      source.replacingOccurrences(of: "tools: list_tasks, read_record", with: "tools: shell"),
      source.replacingOccurrences(of: "permissions: memora.read", with: "run: python secret.py"),
      source.replacingOccurrences(of: "name: 会議フォロー", with: "name: 会議\nname: 上書き"),
      source.replacingOccurrences(of: "description: 決定とタスクを確認", with: "description:"),
      String(repeating: "x", count: 32 * 1024 + 1)
    ] {
      do { _ = try MemoraSkillMarkdown.parse(invalid, allowedTools: known); preconditionFailure("Invalid skill accepted") } catch {}
    }
    print("DiscoverySkillChecks: passed (local relevance/order, reusable drafts, name/keyword selection, disable, size validation without truncation, Markdown round-trip, untrusted/unknown/script metadata rejection)")
  }
}
