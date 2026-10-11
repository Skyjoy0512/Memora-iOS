import FoundationModels

@available(iOS 26.0, *)
@Generable
struct TemplateSectionDigest {
  @Guide(description: "指定された見出しごとの確認できる内容。")
  var sections: [TemplateSectionItems]
}
