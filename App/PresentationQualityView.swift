import SwiftUI

struct PresentationQualityView: View {
  @Environment(MemoraModel.self) private var model
  var document: MemoraDocument

  var body: some View {
    let issues = PresentationValidator.issues(for: document)
    let evidence = document.presentationEvidence
    DisclosureGroup("品質チェック（\(issues.count)件）") {
      VStack(alignment: .leading, spacing: MemoraSpacing.md) {
        Text("版面・入力・同じ出典の数値を機械検査しています。数値の真偽、日本語の自然さ、論理の妥当性は原資料と照合してください。")
          .foregroundStyle(.secondary)
        if let plan = document.presentationPlan {
          ForEach(plan.reviewNotes(for: document.slides), id: \.self) { Text($0).foregroundStyle(.secondary) }
        } else {
          Text("目的・対象読者・ストーリーラインは未設定です。編集から整理できます。")
            .foregroundStyle(.secondary)
        }
        if issues.isEmpty { Text("機械検査の指摘はありません。") }
        ForEach(issues) { issue in
          let page = document.slides.firstIndex { $0.id == issue.slideID }.map { $0 + 1 }
          Text((page.map { "\($0)枚目: " } ?? "") + issue.message)
            .foregroundStyle(issue.isError ? AnyShapeStyle(MemoraPalette.danger) : AnyShapeStyle(.secondary))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, MemoraSpacing.sm)
    }
    .font(.footnote)

    if let evidence {
      DisclosureGroup("根拠パック（候補\(evidence.investigation.consideredSources)件 / 採用\(evidence.investigation.includedSources)件）") {
        VStack(alignment: .leading, spacing: MemoraSpacing.sm) {
          if !evidence.purpose.isEmpty { Text("目的: \(evidence.purpose)") }
          if !evidence.audience.isEmpty { Text("読者: \(evidence.audience)") }
          if !evidence.decisionRequired.isEmpty { Text("判断: \(evidence.decisionRequired)") }
          let revoked = evidence.relatedSources.filter { reference in
            guard reference.id.hasPrefix("record:"),
                  let id = UUID(uuidString: String(reference.id.dropFirst("record:".count))) else { return false }
            return model.meeting(id: id) == nil || !model.allowsRecordAccess(id, purpose: .cloudAI)
          }
          if !revoked.isEmpty {
            Text("根拠のうち\(revoked.count)件は参照権限が変更されています。保存された資料はそのまま残りますが、再生成時は使われません。")
              .foregroundStyle(AnyShapeStyle(MemoraPalette.danger))
          }
          if let deck = evidence.previousFinalDeck {
            Text("前回: \(deck.title)\(deck.isFinal ? "（最終版）" : "（草稿）")")
          }
          if !evidence.changesSincePreviousDeck.isEmpty {
            Text("前回からの変更").foregroundStyle(.secondary)
            ForEach(evidence.changesSincePreviousDeck, id: \.self) { Text("・\($0)") }
          }
          if !evidence.investigation.topics.isEmpty {
            Text("検索語: " + evidence.investigation.topics.prefix(8).joined(separator: "、"))
          }
          let current = visibleDecisions(evidence).filter(\.isCurrent)
          if !current.isEmpty {
            Text("現在の決定").foregroundStyle(.secondary)
            ForEach(current.prefix(5), id: \.id) { decision in
              Text("・\(decision.statement)（\(decision.date.formatted(date: .numeric, time: .omitted)) / 出典 \(decision.sourceID)）")
            }
          }
          if !evidence.contradictions.isEmpty {
            Text("矛盾").foregroundStyle(.secondary)
            ForEach(evidence.contradictions.prefix(3), id: \.self) { Text("・\($0)") }
          }
          if !evidence.gaps.isEmpty {
            Text("不足").foregroundStyle(.secondary)
            ForEach(evidence.gaps, id: \.self) { Text("・\($0)") }
          }
          if !evidence.unconfirmed.isEmpty {
            Text("未確認").foregroundStyle(.secondary)
            ForEach(evidence.unconfirmed.prefix(5), id: \.self) { Text("・\($0)") }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, MemoraSpacing.sm)
      }
      .font(.footnote)
    }
  }

  /// A record whose cloud permission was revoked after the deck was made must
  /// not be shown as a current decision from the saved pack.
  private func visibleDecisions(_ evidence: PresentationEvidencePack) -> [PresentationEvidencePack.DecisionEntry] {
    evidence.decisions.filter { decision in
      guard decision.sourceID.hasPrefix("record:"),
            let id = UUID(uuidString: String(decision.sourceID.dropFirst("record:".count))) else { return true }
      return model.meeting(id: id) != nil && model.allowsRecordAccess(id, purpose: .cloudAI)
    }
  }
}
