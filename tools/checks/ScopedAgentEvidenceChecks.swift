import Foundation

@main
struct ScopedAgentEvidenceChecks {
  static func main() {
    let local = ProjectCitation.Target.source(UUID())
    let other = ProjectCitation.Target.source(UUID())
    let first = ProjectCitation(target: local, title: "対象のPDF", excerpt: "会議の結論", page: 1)
    var registry = ScopedAgentEvidence(characterBudget: 2_000)
    let opening = registry.register([first], allowed: [local])
    precondition(!opening.isError && opening.text.contains("【資料1】") && opening.text.contains("ページ1"))
    precondition(registry.target(for: local.identifier.uuidString) == local)
    precondition(registry.target(for: other.identifier.uuidString) == nil)
    precondition(registry.target(for: local.identifier.uuidString, submitted: []) == nil)
    precondition(registry.target(for: local.identifier.uuidString, submitted: [local]) == local)
    let second = ProjectCitation(target: local, title: first.title, excerpt: "続きの内容", page: 2)
    let expanded = registry.register([second], allowed: [local])
    precondition(expanded.text.contains("【資料2】") && registry.references.count == 2)
    let repeated = registry.register([first], allowed: [local])
    precondition(repeated.text.contains("【資料1】") && registry.references.count == 2)
    let before = registry.references
    let invalid = registry.register([second, ProjectCitation(target: other, title: "別のプロジェクト", excerpt: "非公開")], allowed: [local])
    precondition(invalid.isError && registry.references == before && !invalid.text.contains("非公開"))
    let revoked = registry.register([first], allowed: [])
    precondition(revoked.isError && registry.references == before)
    let resolved = ProjectContextBuilder.cited("結論【資料1】、続き【資料2】、架空【資料99】", from: registry.references)
    precondition(resolved == [first, second])

    let reusedID = UUID()
    let source = ProjectCitation.Target.source(reusedID), meeting = ProjectCitation.Target.meeting(reusedID)
    var ambiguous = ScopedAgentEvidence(characterBudget: 2_000)
    _ = ambiguous.register([ProjectCitation(target: source, title: "資料", excerpt: "本文"),
      ProjectCitation(target: meeting, title: "録音", excerpt: "本文")], allowed: [source, meeting])
    precondition(ambiguous.target(for: reusedID.uuidString) == nil)

    let recordDate = Date(timeIntervalSince1970: 1_789_560_000)
    var dated = ProjectCitation(target: meeting, title: "公開方針", excerpt: "公開を決めた", time: 480, recordedAt: recordDate)
    var recordEvidence = ScopedAgentEvidence(characterBudget: 800)
    let firstDate = recordEvidence.register([dated], allowed: [meeting])
    precondition(firstDate.text.contains("【資料1】") && firstDate.text.contains("記録日") && firstDate.text.contains("録音内 480秒"))
    dated.recordedAt = recordDate.addingTimeInterval(86_400)
    let revisedDate = recordEvidence.register([dated], allowed: [meeting])
    precondition(revisedDate.text.contains("【資料2】") && recordEvidence.references.last?.recordedAt == dated.recordedAt)
    var photoCitation = dated
    photoCitation.photo = .init(name: "whiteboard.jpg", byteCount: 2_048, modifiedAt: recordDate, textReadAt: recordDate)
    let refused = recordEvidence.register([photoCitation], allowed: [meeting])
    precondition(refused.isError && !refused.text.contains(photoCitation.excerpt) && recordEvidence.references.count == 2)

    var tiny = ScopedAgentEvidence(characterBudget: 10)
    precondition(tiny.register([first], allowed: [local]).isError && tiny.references.isEmpty)
    var bounded = ScopedAgentEvidence(characterBudget: 20_000)
    let many = (0..<30).map { index in ProjectCitation(target: local, title: "資料", excerpt: "本文\(index)", page: index + 1) }
    _ = bounded.register(many, allowed: [local])
    precondition(bounded.references.count == 24)
    var long = ScopedAgentEvidence(characterBudget: 1_000)
    let outcome = long.register([ProjectCitation(target: local, title: "資料", excerpt: String(repeating: "あ", count: 4_000))], allowed: [local])
    precondition(!outcome.isError && outcome.text.count <= 1_000 && long.references.first?.excerpt.count == 700)
    precondition(long.remainingCharacters == 1_000 - outcome.text.count)
    print("ScopedAgentEvidenceChecks: passed (fixture scope/revoke rejection, stable citations, guessed/ambiguous IDs, source/text limits; no network)")
  }
}
