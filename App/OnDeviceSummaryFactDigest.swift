import FoundationModels


@available(iOS 26.0, *)
@Generable
struct OnDeviceSummaryFactDigest {
  var category: String
  var content: String
  var status: String
  @Guide(description: "この事実の根拠を原文から8文字以上逐語引用。創作しない。")
  var quote: String
}
