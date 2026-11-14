import Foundation

@main
enum AdaptiveSummaryQualityChecks {
  struct Fixture: Decodable {
    var id: Int
    var kind: String
    var profileID: String
    var raw: String
    var title: String
    var overview: String
    var points: [String]
    var decisions: [String]
    var actions: [Action]
    var questions: [String]
    var concerns: [String]
    var expectedFacts: [String]
    struct Action: Decodable { var title: String; var owner: String?; var due: String? }
  }

  static func main() throws {
    let arguments = CommandLine.arguments
    let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
    precondition(fixtures.count == 35 && Set(fixtures.map(\.id)).count == 35)
    let comparisonIDs: Set<Int> = [11, 3, 13, 12, 15, 17, 24]
    let headings = [11: "現行の見積案で進める", 3: "検索APIの実装と負荷試験", 13: "CSV連携が導入の条件",
      12: "音声検索と写真検索の案", 15: "家族との海沿いの散歩", 17: "雨の日の撮影方法", 24: "一括公開から段階公開への変更"]
    var report = "# 同じ入力による要約の比較\n\n基準: 3420946。以下は**原文と期待事実を明示した手作業の抽出fixtureを、実装前後のSwift builderへ同じように渡した比較**です。LLMが生成した要約の比較ではありません。実モデルの抽出精度・幻覚率・トークン実測・処理時間は未検証です。\n\n"
    var metrics: [[String: Any]] = []
    var expectedCount = 0, beforeRetained = 0, afterRetained = 0
    var beforePlaceholders = 0, afterPlaceholders = 0
    // Stateful cases have dedicated production-code harnesses. Rendering a
    // prepared digest cannot prove persistence, cancellation or model reasoning.
    let stateful: Set<Int> = [25, 26, 27, 28, 29, 32, 33, 34]
    for fixture in fixtures where !stateful.contains(fixture.id) {
      let choice: SummaryTemplateChoice
      let beforeChoice: SummaryTemplateChoice
      if fixture.profileID.hasPrefix("builtin."), let template = SummaryTemplate(rawValue: String(fixture.profileID.dropFirst(8))) {
        choice = .builtIn(template); beforeChoice = choice
      } else if fixture.profileID == "content.adaptive" {
        choice = .adaptiveSource; beforeChoice = .adaptiveSource
      } else {
        choice = .market(SummaryTemplateCatalog.template(id: fixture.profileID)!)
        beforeChoice = .market(BaselineSummaryTemplateCatalog.template(id: fixture.profileID)!)
      }
      let title = headings[fixture.id] ?? fixture.title
      let actions = fixture.actions.map { SummaryActionItem(title: $0.title, owner: $0.owner, due: $0.due) }
      for action in fixture.actions {
        if let owner = action.owner { precondition(fixture.raw.contains(owner)) }
        if let due = action.due { precondition(fixture.raw.contains(due)) }
      }
      let topic = SummaryTopic(title: title, startTime: 0, endTime: fixture.id == 24 ? 4_800 : 60,
        points: fixture.points, decisions: fixture.decisions, concerns: fixture.concerns, actions: actions, questions: fixture.questions)
      var input = MeetingSummaryInput(title: title, date: Date(timeIntervalSince1970: 1_700_000_000), duration: fixture.id == 24 ? 4_800 : 60,
        participantNames: [], transcript: [TranscriptSegment(id: UUID(), speaker: "話者1", speakerIsCertain: false, timestamp: 0, text: fixture.raw)], template: choice)
      let started = ContinuousClock.now
      let after = SummaryMarkdownBuilder.build(template: choice, input: input, headline: title, overview: fixture.overview, topics: [topic])
      let elapsed = started.duration(to: .now).components
      input.template = beforeChoice
      let before = BaselineSummaryMarkdownBuilder.build(template: beforeChoice, input: input, headline: title, overview: fixture.overview, topics: [topic])
      let beforeMatches = fixture.expectedFacts.filter { before.contains($0) }.count
      let afterMatches = fixture.expectedFacts.filter { after.contains($0) }.count
      precondition(afterMatches == fixture.expectedFacts.count, "Lost expected fact in \(fixture.kind)")
      let beforeEmpty = placeholderSections(before)
      let afterEmpty = placeholderSections(after)
      precondition(afterEmpty == 0)
      precondition(SummaryResponseParser.generatedMarkdown(after) == after)
      if fixture.actions.isEmpty { precondition(!after.contains("## 次のアクション")) }
      if fixture.decisions.isEmpty { precondition(!after.contains("## 決定事項")) }
      if [4, 5].contains(fixture.id) { precondition(!after.contains("担当: 未定") && !after.contains("期限: 未定")) }
      expectedCount += fixture.expectedFacts.count; beforeRetained += beforeMatches; afterRetained += afterMatches
      beforePlaceholders += beforeEmpty; afterPlaceholders += afterEmpty
      input.template = choice
      let transcript = input.transcript.map { MeetingSummaryInput.cloudLine(for: $0) }.joined(separator: "\n")
      let newTokens = TokenEstimate.tokens(SummaryPrompt.system + SummaryPrompt.document(for: input, transcript: transcript))
      input.template = beforeChoice
      let oldTokens = TokenEstimate.tokens(BaselineSummaryPrompt.system + BaselineSummaryPrompt.document(for: input, transcript: transcript))
      metrics.append(["id": fixture.id, "kind": fixture.kind, "expectedFacts": fixture.expectedFacts.count,
        "beforeRetained": beforeMatches, "afterRetained": afterMatches,
        "beforePlaceholderSections": beforeEmpty, "afterPlaceholderSections": afterEmpty,
        "beforeEstimatedInputTokens": oldTokens, "afterEstimatedInputTokens": newTokens,
        "beforeEstimatedMarkdownTokens": TokenEstimate.tokens(before), "afterEstimatedMarkdownTokens": TokenEstimate.tokens(after),
        "builderMilliseconds": Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15,
        "actualLLMCalls": 0])
      if comparisonIDs.contains(fixture.id) {
        report += "## \(fixture.kind)\n\n原文:\n\n> \(fixture.raw.prefix(1_000).replacingOccurrences(of: "\n", with: "\n> "))\(fixture.raw.count > 1_000 ? "\n> （長文fixtureの続きはJSONに収録）" : "")\n\n変更前:\n\n```markdown\n\(before)\n```\n\n変更後:\n\n```markdown\n\(after)\n```\n\n"
      }
    }
    report += "## fixtureの集計\n\n内容fixture \(metrics.count)件。期待事実 \(expectedCount)件の保持は変更前 \(beforeRetained)件、変更後 \(afterRetained)件。プレースホルダーだけの節は \(beforePlaceholders)件から\(afterPlaceholders)件。状態・保存・固定形式・不完全JSONの8ケースは専用ホスト検証で確認し、この集計に混ぜていません。\n\nトークンはTokenEstimateによる予算用の推定です。Markdown以外の生成JSONの出力量・実際のモデル料金を含みません。builderMillisecondsはホスト上の文書組み立てのみであり、モデル待機・端末速度ではありません。実LLM呼出しは0回です。\n"
    let output = URL(fileURLWithPath: arguments[2], isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    try report.write(to: output.appendingPathComponent("COMPARISON.md"), atomically: true, encoding: .utf8)
    let json = try JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys])
    try json.write(to: output.appendingPathComponent("fixture-metrics.json"))
    let profiles = SummaryTemplateChoice.builtInChoices + SummaryTemplateCatalog.market.map { .market($0) }
    var audit = "# 抽出プロファイルの対応表\n\n用途別55種類 + 基本4種類。ID、追加状態、ユーザー設定、カスタム形式は維持。以下の参考観点は必須の表示見出しではありません。\n\n| ID | 用途 | 抽出観点 | 固有の規則 | 行動 |\n| --- | --- | --- | --- | --- |\n"
    for choice in profiles {
      let profile = choice.extractionProfile
      audit += "| \(choice.id) | \(choice.title) | \(profile.extractionFocus.joined(separator: "、")) | \(profile.domainSpecificRules) | \(profile.actionExtractionPolicy) |\n"
    }
    try audit.write(to: output.appendingPathComponent("PROFILES.md"), atomically: true, encoding: .utf8)
    print("AdaptiveSummaryQualityChecks: \(metrics.count) content fixtures passed; expected facts \(beforeRetained)/\(expectedCount) -> \(afterRetained)/\(expectedCount); placeholder sections \(beforePlaceholders) -> \(afterPlaceholders). 59 profiles audited. Prepared digests, no real model claim.")
  }

  static func placeholderSections(_ markdown: String) -> Int {
    var bodies: [[String]] = [], body: [String] = []
    for line in markdown.components(separatedBy: "\n") {
      if line.hasPrefix("#") { bodies.append(body); body = [] } else { body.append(line) }
    }
    bodies.append(body)
    return bodies.filter { lines in
      let content = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && $0 != "---" }
      return !content.isEmpty && content.allSatisfy { ["なし", "- なし", "記録なし", "- 記録なし", "記載なし", "未定"].contains($0) }
    }.count
  }
}
