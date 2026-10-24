import FoundationModels

@available(iOS 26.0, *)
@Generable
struct OnDeviceSummaryRelationDigest {
  @Guide(description: "pointsかdecisionsにある親の文と完全一致。根拠の発言に含まれる5〜80文字の節。")
  var parent: String
  @Guide(description: "原文に明示された関係の種類。", .anyOf(["reason", "condition", "effect"]))
  var kind: String
  @Guide(description: "根拠の発言行に書かれた時刻。例00:12。同じ時刻が複数ある発言は使わない。")
  var sourceTime: String
  @Guide(description: "親と関係を述べた発言の全文を逐語転記。否定・条件を切り取らず200文字以内。")
  var quote: String
}
