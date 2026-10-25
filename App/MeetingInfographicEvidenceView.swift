import SwiftUI

struct MeetingInfographicEvidenceView: View {
  var document: MeetingInfographic

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("図解の読み方と根拠").font(.title3.bold())
      Text("本文に基づく整理・解釈です。根拠の一致を検証していますが、解釈の正しさを保証するものではありません。")
        .font(.footnote).foregroundStyle(.secondary)
      Text(document.modelLabel).font(.caption).foregroundStyle(.secondary)
      MeetingInfographicEvidenceClaimView(claim: document.content.headline)
      ForEach(document.content.panels) { panel in
        Text(panel.title).font(.headline)
        ForEach(panel.items) { item in MeetingInfographicEvidenceClaimView(claim: item) }
      }
    }.textSelection(.enabled)
  }
}

private struct MeetingInfographicEvidenceClaimView: View {
  var claim: MeetingInfographic.Claim
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(claim.label).font(.caption).foregroundStyle(.secondary)
      Text(claim.text).font(.body.weight(.medium))
      Text("根拠：\(claim.evidence)").font(.footnote).foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
