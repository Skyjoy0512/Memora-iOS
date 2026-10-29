import Foundation

@main
enum PresentationContextChecks {
  static func main() {
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    let sources = [
      PresentationEvidenceSource(id: "record:a", kind: .record, title: "販売システム進捗会議",
        text: "販売システムの本番リリースを決定した。売上は 1200 万円。リスク: 店舗展開の遅延。",
        date: base, permission: .allowed, stance: .fact, confidence: .confirmed),
      PresentationEvidenceSource(id: "record:b", kind: .record, title: "販売システム定例",
        text: "販売システムの本番リリースは延期。売上は 980 万円。未決: 予算の承認。",
        date: base.addingTimeInterval(86_400), permission: .allowed, stance: .fact, confidence: .reported),
      PresentationEvidenceSource(id: "record:denied", kind: .record, title: "役員会 機密",
        text: "販売システムの本番リリースと売上 5000 万円の機密情報。",
        date: base, permission: .denied),
      PresentationEvidenceSource(id: "record:unknown", kind: .record, title: "未判定の記録",
        text: "販売システムの売上 3000 万円。", date: base, permission: .unknown),
      PresentationEvidenceSource(id: "deck:old", kind: .previousDeck, title: "前回最終版",
        text: "前回の販売システム報告。売上 800 万円。", date: base, permission: .allowed, isFinal: true),
      PresentationEvidenceSource(id: "person:a", kind: .person, title: "山田 太郎",
        text: "山田 太郎", permission: .allowed)
    ]
    let decisions = [
      PresentationDecisionRecord(id: "d1", subject: "販売システム", statement: "A案を承認した",
        date: base, status: .approved, decidedBy: "山田 太郎",
        sourceID: "record:a"),
      PresentationDecisionRecord(id: "d2", subject: "販売システム", statement: "B案へ変更した",
        date: base.addingTimeInterval(86_400), status: .changed, decidedBy: nil,
        sourceID: "record:b"),
      PresentationDecisionRecord(id: "d3", subject: "店舗展開", statement: "店舗展開を撤回した",
        date: base.addingTimeInterval(172_800), status: .withdrawn, decidedBy: nil,
        sourceID: "record:b")
    ]
    let request = PresentationContextRequest(purpose: "販売システムの進捗を経営会議へ報告する",
      audience: "経営会議", decisionRequired: "追加投資を承認するか", query: "販売システム 進捗 予算")
    let pack = PresentationContextBuilder.build(request: request, sources: sources,
      decisions: decisions, characterBudget: 8_000)

    precondition(pack.relatedSources.contains { $0.id == "record:a" })
    precondition(!pack.relatedSources.contains { $0.id == "record:denied" })
    precondition(!pack.keyFacts.contains { $0.sourceID == "record:denied" })
    precondition(!pack.keyFacts.contains { $0.sourceID == "record:unknown" })
    precondition(pack.permissions.contains { $0.id == "record:denied" })
    precondition(pack.unconfirmed.contains { $0.contains("機密") })
    precondition(pack.previousFinalDeck?.id == "deck:old")
    precondition(pack.keyFacts.contains { $0.sourceID == "deck:old" })

    let byID = Dictionary(uniqueKeysWithValues: pack.decisions.map { ($0.id, $0) })
    precondition(byID["d2"]?.isCurrent == true)
    precondition(byID["d1"]?.isCurrent == false)
    precondition(byID["d3"]?.isCurrent == false)
    precondition(pack.decisions.contains { $0.status == .withdrawn })
    precondition(pack.decisions.contains { $0.decidedBy == nil })
    precondition(pack.unconfirmed.contains { $0.contains("決定者") })
    precondition(pack.stakeholders.contains { $0.name == "山田 太郎" })

    precondition(!pack.contradictions.isEmpty)
    precondition(pack.contradictions.contains { $0.contains("数値が異なります") })
    precondition(!pack.metrics.isEmpty)
    precondition(pack.risks.contains { $0.contains("遅延") })
    precondition(pack.timeline.count >= 2)

    let rendered = pack.render()
    precondition(rendered.contains("[record:a]"))
    precondition(rendered.contains("現行"))
    precondition(rendered.contains("履歴"))
    precondition(!rendered.contains("record:denied"))
    precondition(pack.estimatedTokens > 0)

    // A small budget must not let one source fill the whole pack.
    let small = PresentationContextBuilder.build(request: request, sources: sources,
      decisions: decisions, characterBudget: 600)
    precondition(small.keyFacts.reduce(0) { $0 + $1.text.count } <= 1_000)

    // Withdrawing the newest decision leaves history but no current decision.
    let withdrawn = PresentationContextBuilder.resolveDecisions([
      PresentationDecisionRecord(id: "x1", subject: "方針", statement: "A案を承認",
        date: base, status: .approved, decidedBy: nil, sourceID: "s"),
      PresentationDecisionRecord(id: "x2", subject: "方針", statement: "A案を撤回",
        date: base.addingTimeInterval(60), status: .withdrawn, decidedBy: nil, sourceID: "s")
    ])
    precondition(withdrawn.allSatisfy { !$0.isCurrent })
    precondition(withdrawn.count == 2)

    print("PresentationContextChecks: passed (permission gate, final-deck reuse, decision lineage, contradictions, metrics, bounded pack)")
  }
}
