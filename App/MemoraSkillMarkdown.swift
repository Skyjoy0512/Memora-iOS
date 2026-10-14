import Foundation

enum MemoraSkillMarkdown {
  enum Failure: LocalizedError {
    case invalid
    var errorDescription: String? { "スキルを読み込めません。名前・用途・手順と、対応するツール名を確認してください（最大32KB）。" }
  }

  static func read(_ url: URL) throws -> String {
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    guard let data = try handle.read(upToCount: 32 * 1024 + 1), data.count <= 32 * 1024,
          let text = String(data: data, encoding: .utf8) else { throw Failure.invalid }
    return text
  }

  /// A bounded text format, not a YAML evaluator or executable skill package.
  static func parse(_ markdown: String, allowedTools: Set<String>) throws -> MemoraSkill {
    guard markdown.utf8.count <= 32 * 1024 else { throw Failure.invalid }
    let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---"), end <= 24 else { throw Failure.invalid }
    var metadata: [String: String] = [:]
    let keys: Set<String> = ["name", "description", "tools", "keywords", "permissions"]
    for line in lines[1..<end] where !line.trimmingCharacters(in: .whitespaces).isEmpty {
      guard let separator = line.firstIndex(of: ":") else { throw Failure.invalid }
      let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
      guard keys.contains(key), metadata[key] == nil else { throw Failure.invalid }
      metadata[key] = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
    }
    func list(_ key: String) -> [String] {
      (metadata[key] ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        .components(separatedBy: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) }.filter { !$0.isEmpty }
    }
    let skill = MemoraSkill(id: "custom-" + UUID().uuidString, name: metadata["name"] ?? "", summary: metadata["description"] ?? "",
      instructions: lines[(end + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
      keywords: list("keywords"), declaredToolNames: list("tools"), declaredPermissions: list("permissions"))
    guard valid(skill), skill.toolNames.allSatisfy(allowedTools.contains) else { throw Failure.invalid }
    return skill
  }

  static func valid(_ skill: MemoraSkill) -> Bool {
    skill.id.hasPrefix("custom-") && UUID(uuidString: String(skill.id.dropFirst(7))) != nil
      && (1...80).contains(skill.name.count) && !skill.name.contains("\n")
      && (1...400).contains(skill.summary.count) && !skill.summary.contains("\n")
      && (1...6_000).contains(skill.instructions.count)
      && skill.keywords.count <= 8 && skill.keywords.allSatisfy { (1...40).contains($0.count) && !$0.contains("\n") }
      && skill.toolNames.count <= 16 && Set(skill.toolNames).count == skill.toolNames.count
      && skill.toolNames.allSatisfy { (1...128).contains($0.count) && !$0.contains("\n") }
      && (skill.declaredPermissions ?? []).count <= 8
      && (skill.declaredPermissions ?? []).allSatisfy { (1...120).contains($0.count) && !$0.contains("\n") }
  }
}
