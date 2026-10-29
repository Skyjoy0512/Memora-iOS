import Foundation

@main
enum PresentationDeepContextChecks {
  static func main() {
    let start = ContinuousClock.now
    var failures = 0
    func require(_ condition: Bool, _ message: String) {
      if !condition { failures += 1; print("FAIL: \(message)") }
    }

    // A cross-year archive: mostly unrelated records, a few that matter, and
    // records the person has not allowed.
    var sources: [PresentationEvidenceSource] = []
    let base = Date(timeIntervalSince1970: 1_600_000_000)
    for index in 0..<120 {
      let topic = index % 7 == 0 ? "サブスク販売システムの定期課金" : "社内総務の備品更新"
      sources.append(.init(id: "record:archive\(index)", kind: .record,
        title: "定例会議 \(index)", text: "\(topic)。議題 \(index) の確認。",
        date: base.addingTimeInterval(Double(index) * 86_400), permission: .allowed))
    }
    sources.append(.init(id: "record:seed", kind: .record, title: "販売システム検討会",
      text: "サブスク販売システムの進捗を確認。定期課金の設計を検討した。",
      date: base.addingTimeInterval(200 * 86_400), permission: .allowed,
      stance: .fact, confidence: .confirmed))
    // The important record does not use the request's word; only the second
    // pass ties it to the seed's "定期課金".
    sources.append(.init(id: "record:important", kind: .record, title: "本番移行の判断",
      text: "定期課金の本番移行を承認した。売上は 1,240 万円。",
      date: base.addingTimeInterval(260 * 86_400), permission: .allowed,
      stance: .fact, confidence: .confirmed))
    sources.append(.init(id: "record:old", kind: .record, title: "旧定例",
      text: "サブスク販売システムの進捗。売上は 900 万円。",
      date: base.addingTimeInterval(120 * 86_400), permission: .allowed))
    sources.append(.init(id: "record:revoked", kind: .record, title: "アクセス権取消済み",
      text: "サブスク販売システムの定期課金 売上 9,999 万円の機密。",
      date: base.addingTimeInterval(300 * 86_400), permission: .denied))
    sources.append(.init(id: "record:unknown", kind: .record, title: "未判定",
      text: "サブスク販売システム 売上 8,888 万円。", permission: .unknown))
    sources.append(.init(id: "deck:final", kind: .previousDeck, title: "前回最終版 販売システム",
      text: "前回の販売システム報告。売上 800 万円。", date: base, permission: .allowed,
      version: "3", isFinal: true))
    sources.append(.init(id: "person:a", kind: .person, title: "田中 一郎",
      text: "田中 一郎", permission: .allowed))
    sources.append(.init(id: "person:b", kind: .person, title: "田中 一郎",
      text: "田中 一郎", permission: .allowed))
    sources.append(.init(id: "memory:a", kind: .memory, title: "長期メモリ",
      text: "販売システムの担当は田中。", date: base, permission: .allowed))

    let decisions = [
      PresentationDecisionRecord(id: "d-old", subject: "サブスク販売システムのリリース",
        statement: "A案でリリースする", date: base.addingTimeInterval(100 * 86_400),
        status: .approved, decidedBy: "田中 一郎", sourceID: "record:seed"),
      PresentationDecisionRecord(id: "d-new", subject: "サブスク販売システムのリリース",
        statement: "B案へ変更する", date: base.addingTimeInterval(260 * 86_400),
        status: .changed, decidedBy: nil, sourceID: "record:important"),
      PresentationDecisionRecord(id: "d-cancel", subject: "旧システム移行",
        statement: "旧システム移行を撤回する", date: base.addingTimeInterval(280 * 86_400),
        status: .withdrawn, decidedBy: "田中 一郎", sourceID: "record:important"),
      PresentationDecisionRecord(id: "d-explicit-old", subject: "移行方針",
        statement: "従来方式で進める", date: base.addingTimeInterval(90 * 86_400),
        status: .approved, decidedBy: "田中 一郎", sourceID: "record:seed"),
      PresentationDecisionRecord(id: "d-explicit-new", subject: "新しい方式",
        statement: "新方式へ切り替える", date: base.addingTimeInterval(270 * 86_400),
        status: .changed, decidedBy: nil, supersedes: "d-explicit-old",
        sourceID: "record:important")
    ]
    let request = PresentationContextRequest(purpose: "経営会議へサブスク販売システムの進捗を報告",
      audience: "経営会議", decisionRequired: "追加投資を承認するか",
      query: "サブスク販売システム 進捗", projectName: "販売システム刷新")
    let pack = PresentationContextBuilder.build(request: request, sources: sources,
      decisions: decisions, characterBudget: 30_000)

    require(pack.investigation.searchPasses == 2, "second search pass should run")
    require(pack.investigation.expandedTopics.contains("定期"), "expanded topic should be recorded")
    require(pack.investigation.allowedSources == 127, "allowed sources counted")
    require(pack.investigation.includedSources > 0 && pack.investigation.includedSources < 125, "bounded inclusion")
    require(pack.keyFacts.contains { $0.sourceID == "record:important" }, "important record with a different word is recalled")
    require(pack.keyFacts.contains { $0.sourceID == "record:seed" }, "seed record is retained")
    require(pack.keyFacts.contains { $0.sourceID == "deck:final" }, "final deck is retained")
    require(!pack.keyFacts.contains { $0.sourceID == "record:revoked" }, "revoked record is never read")
    require(!pack.keyFacts.contains { $0.sourceID == "record:unknown" }, "unconfirmed permission is not sent")
    require(pack.permissions.contains { $0.id == "record:revoked" }, "revoked is reported as a permission gap")
    require(pack.previousFinalDeck?.isFinal == true && pack.previousFinalDeck?.version == "3", "final deck identified")
    require(pack.decisions.contains { $0.id == "d-new" && $0.isCurrent }, "new decision is current")
    require(pack.decisions.contains { $0.id == "d-old" && !$0.isCurrent }, "old decision is history")
    require(pack.decisions.contains { $0.id == "d-cancel" && !$0.isCurrent }, "withdrawn decision is not current")
    require(pack.decisions.contains { $0.id == "d-explicit-old" && !$0.isCurrent }, "explicitly superseded decision is history")
    require(pack.decisions.contains { $0.id == "d-explicit-new" && $0.isCurrent }, "the explicit superseder is current")
    require(pack.decisions.contains { $0.decidedBy == nil } && pack.unconfirmed.contains { $0.contains("決定者") }, "missing decider is reported")
    require(pack.contradictions.contains { $0.contains("数値が異なります") }, "number conflict is reported")
    require(pack.metrics.contains { $0.value.contains("1240") || $0.value.contains("1,240") }, "new metric retained")
    require(pack.stakeholders.filter { $0.name == "田中 一郎" }.count <= 2, "same-name people stay separate by ID")
    require(pack.render().contains("[record:important]"), "source ID kept in rendered prompt")
    require(!pack.changesSincePreviousDeck.isEmpty, "changes against the previous deck are listed")
    require(pack.changesSincePreviousDeck.contains { $0.contains("800") }, "old number is flagged as unconfirmed")
    require(pack.render().contains("前回最終版からの変更"), "changes are in the prompt block")
    require(!pack.render().contains("record:revoked"), "revoked source absent from prompt")

    // Scenario: a proposal with no numeric basis must say so, not invent one.
    let proposal = PresentationContextBuilder.build(
      request: PresentationContextRequest(purpose: "新規顧客へ提案", audience: "顧客",
        decisionRequired: "導入可否", query: "顧客 課題 競合"),
      sources: [.init(id: "record:proposal", kind: .record, title: "顧客ヒアリング",
        text: "顧客の課題は手作業の集計。競合Aを検討中。", date: base, permission: .allowed)],
      characterBudget: 4_000)
    require(proposal.gaps.contains { $0.contains("数値の根拠") }, "missing metrics becomes a gap")
    require(proposal.gaps.contains { $0.contains("前回の最終提出版") }, "missing previous deck becomes a gap")

    // A large archive must stay bounded in time and text.
    let elapsed = start.duration(to: .now)
    require(elapsed < .seconds(5), "builder stays within five seconds for 125 sources")
    require(pack.keyFacts.reduce(0) { $0 + $1.text.count } <= 30_000, "key facts respect the character budget")

    if failures == 0 {
      print("PresentationDeepContextChecks: passed (\(sources.count) sources, 2 passes, permission gate, decision lineage, contradictions, same-name IDs, gaps, bounded in \(elapsed))")
    } else {
      print("PresentationDeepContextChecks: \(failures) failure(s)")
      exit(1)
    }
  }
}
