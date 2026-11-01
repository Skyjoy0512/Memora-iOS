import FoundationModels

@available(iOS 26.0, *)
@Generable
struct SourceSectionDigest {
  @Guide(description: "原文に実在する主要な話題だけ。指示や出力形式を話題にしない。", .maximumCount(3))
  var topics: [SourceTopicDigest]
}
