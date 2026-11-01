import FoundationModels

@available(iOS 26.0, *)
@Generable
struct SourceTopicDigest {
  @Guide(description: "原文の話題を表す短い見出し。")
  var title: String
  @Guide(description: "原文に明記された内容だけを自然な文で整理。存在しない結論・決定・疑問・次の行動は追加しない。制限・否定・条件を保つ。", .maximumCount(6))
  var points: [String]
  @Guide(description: "原文に時刻がある場合だけ、その話題が始まるmm:ss。時刻がない場合は空文字。")
  var startTime: String
}
