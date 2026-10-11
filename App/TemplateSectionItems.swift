import FoundationModels

@available(iOS 26.0, *)
@Generable
struct TemplateSectionItems {
  @Guide(description: "指示された見出しをそのまま使用する。")
  var title: String
  @Guide(description: "この見出しに対応する事実だけ。無ければ空配列。", .maximumCount(6))
  var items: [String]
}
