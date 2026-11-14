import Foundation

/// Normalizes editable fields without changing identity, permissions or scope.
struct SkillEditorInput {
  var skill: MemoraSkill
  var keywords: String

  var normalizedSkill: MemoraSkill {
    var candidate = skill
    candidate.name = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
    candidate.summary = candidate.summary.trimmingCharacters(in: .whitespacesAndNewlines)
    candidate.instructions = candidate.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
    var seen: Set<String> = []
    candidate.keywords = keywords.components(separatedBy: CharacterSet(charactersIn: ",、，"))
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    return candidate
  }

  var validationMessage: String? {
    let candidate = normalizedSkill
    if candidate.name.count > 80 { return "スキル名は80文字以内にしてください。" }
    if candidate.summary.count > 400 { return "用途は400文字以内にしてください。" }
    if candidate.instructions.count > 6_000 { return "手順は6,000文字以内にしてください。内容は切り詰めずに残しています。" }
    if candidate.keywords.count > 8 { return "キーワードは8個までにしてください。" }
    if candidate.keywords.contains(where: { $0.count > 40 || $0.contains("\n") }) {
      return "キーワードはそれぞれ40文字以内・1行で入力してください。"
    }
    if candidate.toolNames.count > 16 { return "利用するツールは16個まで選べます。" }
    if let output = candidate.outputDescription, output.isEmpty || output.count > 240 || output.contains("\n") {
      return "できあがるものは240文字以内・1行で入力してください。"
    }
    if let examples = candidate.examplePrompts, examples.count > 3 || examples.contains(where: { $0.isEmpty || $0.count > 300 || $0.contains("\n") }) {
      return "依頼の例は各300文字以内、空行を入れずに3件まで入力してください。"
    }
    if candidate.name.isEmpty { return "スキル名を入力してください。" }
    if candidate.summary.isEmpty { return "いつ使うか・何をするかを入力してください。" }
    if candidate.instructions.isEmpty { return "繰り返し使う作業手順を入力してください。" }
    if candidate.name.contains("\n") || candidate.summary.contains("\n") {
      return "スキル名と用途は、それぞれ1行で入力してください。"
    }
    return MemoraSkillMarkdown.valid(candidate) ? nil : "名前・用途・手順と、利用するツールを確認してください。"
  }

  func hasChanges(from original: MemoraSkill) -> Bool {
    let baseline = Self(skill: original, keywords: original.keywords.joined(separator: ", ")).normalizedSkill
    let candidate = normalizedSkill
    return candidate.name != baseline.name || candidate.summary != baseline.summary
      || candidate.instructions != baseline.instructions || candidate.keywords != baseline.keywords
      || candidate.toolNames != baseline.toolNames
      || candidate.category != baseline.category || candidate.examplePrompts != baseline.examplePrompts
      || candidate.outputDescription != baseline.outputDescription
  }
}
