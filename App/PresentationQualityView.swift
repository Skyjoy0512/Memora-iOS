import SwiftUI

struct PresentationQualityView: View {
  @Environment(MemoraModel.self) private var model
  var document: MemoraDocument
  var editSlide: (UUID) -> Void = { _ in }
  @State private var selectedEvidenceSource: PresentationEvidencePack.SourceReference?

  var body: some View {
    let issues = PresentationValidator.issues(for: document)
    let evidence = document.presentationEvidence
    let errors = issues.filter(\.isError)
    let sourceRows = model.artifactSourceRows(provenance: document.provenance,
      meetingIDs: document.sourceRecordIDs ?? [], projectFileIDs: document.sourceProjectFileIDs ?? [])
    VStack(alignment: .leading, spacing: MemoraSpacing.sm) {
      Text("品質チェック: 要修正\(errors.count)件・要確認\(issues.count - errors.count)件")
        .font(.subheadline.weight(.semibold))
      if let first = errors.first {
        Text(first.message).font(.footnote).foregroundStyle(MemoraPalette.danger)
        Button { editSlide(first.slideID) } label: {
          Label("最初の指摘を修正", icon: .pencil)
            .frame(minHeight: 44).contentShape(Rectangle())
        }
          .buttonStyle(.bordered)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
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
          Button { editSlide(issue.slideID) } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text((page.map { "\($0)枚目・" } ?? "") + (issue.isError ? "要修正" : "要確認")).fontWeight(.semibold)
              Text(issue.message)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .foregroundStyle(issue.isError ? AnyShapeStyle(MemoraPalette.danger) : AnyShapeStyle(.secondary))
          .accessibilityHint("該当スライドの編集を開きます")
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
            !model.presentationEvidenceSourceAllowsCloud(reference)
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
              VStack(alignment: .leading, spacing: 4) {
                Text("・\(decision.statement)（\(MemoraFormat.documentDate(decision.date))）")
                if let reference = evidence.relatedSources.first(where: { $0.id == decision.sourceID }),
                   let target = ArtifactSourceTarget.presentationSourceID(reference.id),
                   let row = sourceRows.first(where: { $0.target == target && $0.canOpen }) {
                  ArtifactSourceLink(row: row) { selectedEvidenceSource = reference }
                } else {
                  Text("出典の詳細は現在開けません").foregroundStyle(.secondary)
                }
              }
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
      .sheet(item: $selectedEvidenceSource) { reference in
        if document.provenance?.workspaceID == model.currentTeamID,
           model.presentationEvidenceSourceAllowsCloud(reference),
           let target = ArtifactSourceTarget.presentationSourceID(reference.id) {
          ArtifactSourceDetailView(target: target, workspaceID: document.provenance?.workspaceID)
        } else {
          ContentUnavailableView("元の情報を開けません", icon: .lockShield,
            description: Text("ワークスペースと参照権限を確認してください。"))
        }
      }
    }
  }

  /// A record whose cloud permission was revoked after the deck was made must
  /// not be shown as a current decision from the saved pack.
  private func visibleDecisions(_ evidence: PresentationEvidencePack) -> [PresentationEvidencePack.DecisionEntry] {
    guard document.provenance?.workspaceID == model.currentTeamID,
          document.provenance?.isValid ?? true else { return [] }
    return evidence.decisions.filter { decision in
      guard let source = evidence.relatedSources.first(where: { $0.id == decision.sourceID }) else { return false }
      return model.presentationEvidenceSourceAllowsCloud(source)
    }
  }
}
