import Foundation

struct MarketplaceDefinition: Codable {
  enum Kind: String, Codable { case skill, template }
  var version = 1
  var kind: Kind
  var skill: MemoraSkill?
  var template: SummaryMarketTemplate?

  init(skill: MemoraSkill) {
    kind = .skill
    var skill = skill
    skill.declaredToolNames = skill.toolNames
    self.skill = skill
  }
  init(template: SummaryMarketTemplate) { kind = .template; self.template = template }
  var title: String { skill?.name ?? template?.title ?? "" }
  var summary: String { skill?.summary ?? template?.detail ?? "" }
  var shareText: String { (try? String(decoding: JSONEncoder().encode(self), as: UTF8.self)) ?? "" }

  func validated(allowedTools: Set<String>) throws -> Self {
    guard version == 1, let bytes = try? JSONEncoder().encode(self), bytes.count <= 32 * 1024 else { throw CommunityError.invalidContent }
    var result = self
    switch kind {
    case .skill:
      guard template == nil, var skill else { throw CommunityError.invalidContent }
      skill.declaredToolNames = skill.toolNames
      skill.id = "custom-" + UUID().uuidString
      guard MemoraSkillMarkdown.valid(skill), skill.toolNames.allSatisfy(allowedTools.contains),
            (skill.scopes ?? [.global]).count <= 4,
            (skill.iconIdentifier?.count ?? 0) <= 80 else { throw CommunityError.invalidContent }
      result.skill = skill
    case .template:
      guard skill == nil, var template,
            (1...80).contains(template.title.count), !template.title.contains(where: { $0.isNewline }), template.detail.count <= 400,
            template.sections.count <= 12, Set(template.sections).count == template.sections.count, template.sections.allSatisfy({ (1...80).contains($0.count) && !$0.contains(where: { $0.isNewline }) }),
            template.focus.count <= 3000, template.prompt.count <= 6000,
            template.usesPrompt || !template.sections.isEmpty else { throw CommunityError.invalidContent }
      template.id = "custom.community." + UUID().uuidString
      template.isCustom = true
      template.occupationTags = []; template.useCaseTags = []
      template.lead = template.title
      result.template = template
    }
    return result
  }

  static func read(_ text: String, allowedTools: Set<String>) throws -> Self {
    guard text.utf8.count <= 32 * 1024 else { throw CommunityError.invalidContent }
    if let data = text.data(using: .utf8), let value = try? JSONDecoder().decode(Self.self, from: data) {
      return try value.validated(allowedTools: allowedTools)
    }
    return try Self(skill: MemoraSkillMarkdown.parse(text, allowedTools: allowedTools)).validated(allowedTools: allowedTools)
  }
}
