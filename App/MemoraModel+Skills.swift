import Foundation

extension MemoraModel {
  var skillCatalog: [MemoraSkill] { MemoraSkill.bundled + customSkills }

  func saveCustomSkill(_ skill: MemoraSkill) -> Bool {
    let knownTools = Set(AgentTool.allCases.map(\.rawValue))
    guard !isRestoring, MemoraSkillMarkdown.valid(skill), skill.toolNames.allSatisfy(knownTools.contains) else { return false }
    var candidate = customSkills
    if let index = candidate.firstIndex(where: { $0.id == skill.id }) { candidate[index] = skill }
    else { guard candidate.count < 30 else { return false }; candidate.append(skill) }
    guard persistNow(candidate, forKey: StorageKey.customSkills) else { return false }
    customSkills = candidate
    return true
  }

  func deleteCustomSkill(_ id: String) -> Bool {
    guard customSkills.contains(where: { $0.id == id }), !isRestoring else { return false }
    let candidate = customSkills.filter { $0.id != id }
    guard persistNow(candidate, forKey: StorageKey.customSkills) else { return false }
    customSkills = candidate
    disabledSkillIDs.removeAll { $0 == id }
    return true
  }

  func recordSkillSelection(_ ids: [String]) {
    guard !ids.isEmpty else { return }
    let validIDs = Set(skillCatalog.map(\.id))
    var candidate = skillLastSelectedAt.filter { validIDs.contains($0.key) }
    for id in ids where validIDs.contains(id) { candidate[id] = .now }
    let history = candidate.map { SkillSelection(skillID: $0.key, selectedAt: $0.value) }
    guard persistNow(history, forKey: StorageKey.skillUsage) else { return }
    skillLastSelectedAt = candidate
  }
}
