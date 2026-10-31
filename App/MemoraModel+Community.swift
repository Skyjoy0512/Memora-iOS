import Foundation

extension MemoraModel {
  func hasCommunityItem(_ post: CommunityPost) -> Bool {
    switch post.definition.kind {
    case .skill: customSkills.contains { $0.id == "custom-" + post.id }
    case .template: customTemplates.contains { $0.id == "custom.community." + post.id }
    }
  }

  func installCommunityDefinition(_ definition: MarketplaceDefinition, postID: String) throws {
    guard UUID(uuidString: postID) != nil else { throw CommunityError.invalidContent }
    let content = try definition.validated(allowedTools: Set(AgentTool.allCases.map(\.rawValue)))
    switch content.kind {
    case .skill:
      guard var skill = content.skill else { throw CommunityError.invalidContent }
      skill.id = "custom-" + postID
      // Reopening a downloaded post must not overwrite the person's edited copy.
      guard !customSkills.contains(where: { $0.id == skill.id }) else { return }
      guard saveCustomSkill(skill) else { throw CommunityError.saveFailed }
    case .template:
      guard var template = content.template else { throw CommunityError.invalidContent }
      template.id = "custom.community." + postID
      guard !customTemplates.contains(where: { $0.id == template.id }) else { return }
      guard saveCustomTemplate(template) else { throw CommunityError.saveFailed }
    }
  }
}
