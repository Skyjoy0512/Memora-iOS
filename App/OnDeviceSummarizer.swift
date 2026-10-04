import Foundation
import FoundationModels

/// Summarizes with Apple's on-device model. Its window is about 4,096 tokens,
/// so a real meeting never fits at once: the transcript is read section by
/// section into structured topic notes (guided generation keeps a small model
/// on the format), a short overview is written from those notes, and the
/// document itself is laid out in Swift. Less nuanced than the cloud pass, but
/// it works for any length and nothing leaves the device.
@available(iOS 26.0, *)
enum OnDeviceSummarizer {
  static func summarize(
    _ input: MeetingSummaryInput,
    progress: @escaping @MainActor (String) -> Void
  ) async -> Result<MeetingSummary, AIAnswerFailure> {
    let model = SystemLanguageModel.default
    guard model.isAvailable else { return .failure(.noEngine) }

    let sections = sectioned(input.transcript, characterLimit: sectionCharacterLimit(model))
    var topics: [SummaryTopic] = []

    for (index, section) in sections.enumerated() {
      guard !Task.isCancelled else { return .failure(.cancelled) }
      await progress("区間を整理中（\(index + 1)/\(sections.count)）")
      switch await digest(section, meetingEnd: input.duration) {
      case .success(let found):
        topics.append(contentsOf: found)
      case .failure(let failure):
        return .failure(failure)
      }
    }
    topics = mergedAcrossSections(topics, meetingEnd: input.duration)
    guard !topics.isEmpty else { return .failure(.empty) }

    guard !Task.isCancelled else { return .failure(.cancelled) }
    await progress("全体の概要をまとめています")
    let overview: Overview
    switch await self.overview(of: topics, input: input, characterLimit: sectionCharacterLimit(model)) {
    case .success(let found):
      overview = found
    case .failure(let failure):
      return .failure(failure)
    }

    let markdown = SummaryMarkdownBuilder.build(
      template: input.template,
      input: input,
      headline: overview.headline,
      overview: overview.overview,
      topics: topics
    )
    let actions = SummaryResponseParser.deduplicated(topics.flatMap(\.actions))
    return .success(MeetingSummary(
      markdown: markdown,
      keyPoints: overview.keyPoints,
      decisions: unique(topics.flatMap(\.decisions)),
      openQuestions: unique(topics.flatMap(\.questions)),
      actions: actions
    ))
  }

  // MARK: - Sections

  /// Half the window goes to the transcript; the rest covers the instructions,
  /// the schema and the answer. Japanese runs about a token per character.
  private static func sectionCharacterLimit(_ model: SystemLanguageModel) -> Int {
    max(800, model.contextSize / 2)
  }

  private static func sectioned(_ transcript: [TranscriptSegment], characterLimit: Int) -> [[TranscriptSegment]] {
    var sections: [[TranscriptSegment]] = []
    var current: [TranscriptSegment] = []
    var length = 0
    for segment in transcript where !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let lineLength = MeetingSummaryInput.line(for: segment).count + 1
      if !current.isEmpty, length + lineLength > characterLimit {
        sections.append(current)
        current = []
        length = 0
      }
      current.append(segment)
      length += lineLength
    }
    if !current.isEmpty { sections.append(current) }
    return sections
  }

  private static let instructions = """
  あなたは会議の文字起こしを整理するアシスタントです。文字起こしにあることだけを書きます。
  人名・数値・日付・金額・固有名詞は文字起こしの表記のまま使い、話者はラベル（例: Speaker 1）で呼びます。
  相槌や言い直しは無視し、議論の中身を具体的に残します。担当者や期限が述べられていなければ「未定」とします。
  発言をそのまま書き写さず、「Speaker 1が〜と述べた」「〜で合意した」のような言い切りの文に要約します。
  \(ReadabilityGuide.compactRules)
  """

  /// One section's topics. A section the model still finds too long is split
  /// in half and read as two, once.
  private static func digest(
    _ section: [TranscriptSegment],
    meetingEnd: TimeInterval,
    allowsSplit: Bool = true
  ) async -> Result<[SummaryTopic], AIAnswerFailure> {
    guard let first = section.first, let last = section.last else { return .success([]) }
    let range = "\(MemoraFormat.duration(first.timestamp))〜\(MemoraFormat.duration(last.timestamp))"
    let prompt = """
    次は会議の文字起こしの一部（\(range)）です。話題ごとに整理してください。

    \(section.map(MeetingSummaryInput.line(for:)).joined(separator: "\n"))
    """

    do {
      let session = LanguageModelSession(instructions: instructions)
      let response = try await session.respond(
        to: prompt,
        generating: SectionDigest.self,
        options: GenerationOptions(temperature: 0.2)
      )
      return .success(response.content.topics.compactMap { topic($0, in: section) })
    } catch {
      let failure = FoundationModelFailure.reason(for: error)
      guard failure == .contextTooLarge, allowsSplit, section.count > 1 else {
        return .failure(failure)
      }
      let middle = section.count / 2
      var topics: [SummaryTopic] = []
      for half in [Array(section[..<middle]), Array(section[middle...])] {
        switch await digest(half, meetingEnd: meetingEnd, allowsSplit: false) {
        case .success(let found): topics.append(contentsOf: found)
        case .failure(let failure): return .failure(failure)
        }
      }
      return .success(topics)
    }
  }

  private static func topic(_ digest: TopicDigest, in section: [TranscriptSegment]) -> SummaryTopic? {
    let title = digest.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let points = clean(digest.points)
    guard !title.isEmpty, !points.isEmpty else { return nil }
    let sectionStart = section.first?.timestamp ?? 0
    let sectionEnd = section.last?.timestamp ?? sectionStart
    // The model reads the time off a line; anything outside the section is
    // a misread, so it falls back to the section's start.
    var start = seconds(digest.startTime) ?? sectionStart
    if start < sectionStart || start > sectionEnd { start = sectionStart }

    return SummaryTopic(
      title: title,
      startTime: start,
      endTime: sectionEnd,
      speakers: clean(digest.speakers),
      points: points,
      decisions: clean(digest.decisions),
      concerns: clean(digest.concerns),
      actions: digest.actions.compactMap { action in
        let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return SummaryActionItem(
          title: title,
          owner: SummaryActionItem.normalized(action.owner),
          due: SummaryActionItem.normalized(action.due)
        )
      },
      questions: clean(digest.questions)
    )
  }

  /// Orders topics by time, sets each one's end to where the next begins, and
  /// joins a topic that ran across a section boundary back into one.
  private static func mergedAcrossSections(_ topics: [SummaryTopic], meetingEnd: TimeInterval) -> [SummaryTopic] {
    let ordered = topics.sorted { $0.startTime < $1.startTime }
    var merged: [SummaryTopic] = []
    for topic in ordered {
      if var previous = merged.last,
         SummaryResponseParser.taskKey(previous.title) == SummaryResponseParser.taskKey(topic.title) {
        previous.speakers = unique(previous.speakers + topic.speakers)
        previous.points += topic.points
        previous.decisions += topic.decisions
        previous.concerns += topic.concerns
        previous.actions += topic.actions
        previous.questions += topic.questions
        merged[merged.count - 1] = previous
      } else {
        merged.append(topic)
      }
    }
    for index in merged.indices {
      merged[index].endTime = index + 1 < merged.count
        ? merged[index + 1].startTime
        : max(meetingEnd, merged[index].endTime)
    }
    return merged
  }

  // MARK: - Overview

  private struct Overview {
    var headline: String
    var overview: String
    var keyPoints: [String]
  }

  private static func overview(
    of topics: [SummaryTopic],
    input: MeetingSummaryInput,
    characterLimit: Int
  ) async -> Result<Overview, AIAnswerFailure> {
    // Titles, decisions and the first points of each topic, trimmed to fit.
    var notes = ""
    for (index, topic) in topics.enumerated() {
      var block = "\(index + 1). \(topic.title)\n"
      block += topic.points.prefix(2).map { "- \($0)" }.joined(separator: "\n")
      if !topic.decisions.isEmpty {
        block += "\n" + topic.decisions.prefix(2).map { "- （決定）\($0)" }.joined(separator: "\n")
      }
      guard notes.count + block.count < characterLimit else { break }
      notes += block + "\n"
    }

    let lens: String = if case .market(let template) = input.template, template.usesPrompt {
      "次の指示に沿って（\(template.prompt.prefix(300))）"
    } else if case .market(let template) = input.template {
      "「\(template.lead)」の観点で"
    } else {
      ""
    }
    let prompt = """
    次は会議「\(input.title)」の話題ごとのメモです。\(lens)会議全体の見出し・概要・重要なポイントをまとめてください。

    \(notes)
    """

    do {
      let session = LanguageModelSession(instructions: instructions)
      let response = try await session.respond(
        to: prompt,
        generating: OverviewDigest.self,
        options: GenerationOptions(temperature: 0.2)
      )
      let content = response.content
      let headline = content.headline.trimmingCharacters(in: .whitespacesAndNewlines)
      return .success(Overview(
        headline: headline.isEmpty ? input.title : headline,
        overview: content.overview.trimmingCharacters(in: .whitespacesAndNewlines),
        // The notes mark decisions with （決定）; that marker is not content.
        keyPoints: clean(content.keyPoints.map { point in
          var point = point
          for marker in ["（決定）", "(決定)", "決定:", "決定："] where point.hasPrefix(marker) {
            point.removeFirst(marker.count)
          }
          return point
        })
      ))
    } catch {
      return .failure(FoundationModelFailure.reason(for: error))
    }
  }

  // MARK: - Helpers

  private static func clean(_ items: [String]) -> [String] {
    unique(items
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { SummaryActionItem.normalized($0) != nil })
  }

  private static func unique(_ items: [String]) -> [String] {
    var seen: Set<String> = []
    return items.filter { seen.insert(SummaryResponseParser.taskKey($0)).inserted }
  }

  /// "mm:ss" or "h:mm:ss" as seconds.
  private static func seconds(_ text: String) -> TimeInterval? {
    let parts = text.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
      .split(separator: ":")
      .compactMap { Double($0) }
    guard (2...3).contains(parts.count) else { return nil }
    return parts.reduce(0) { $0 * 60 + $1 }
  }
}

@available(iOS 26.0, *)
@Generable
private struct SectionDigest {
  @Guide(description: "この区間で話された話題。話題が変わるごとに分ける。", .maximumCount(3))
  var topics: [TopicDigest]
}

@available(iOS 26.0, *)
@Generable
private struct TopicDigest {
  @Guide(description: "話題の短い見出し（20字以内）")
  var title: String
  @Guide(description: "話題が始まった行の時刻（mm:ss）")
  var startTime: String
  @Guide(description: "この話題で発言した話者ラベル")
  var speakers: [String]
  @Guide(description: "誰が何を述べたかが分かる具体的な要点。発言の書き写しではなく言い切りの文で。数値や固有名詞は正確に。", .maximumCount(6))
  var points: [String]
  @Guide(description: "決まったこと。無ければ空。", .maximumCount(4))
  var decisions: [String]
  @Guide(description: "出された課題や懸念。無ければ空。", .maximumCount(3))
  var concerns: [String]
  @Guide(description: "誰かがやると決まった次の行動。無ければ空。", .maximumCount(4))
  var actions: [ActionDigest]
  @Guide(description: "結論が出ずに残った問いを疑問文で。感想や決まったことは含めない。無ければ空。", .maximumCount(3))
  var questions: [String]
}

@available(iOS 26.0, *)
@Generable
private struct ActionDigest {
  @Guide(description: "行動の短い件名")
  var title: String
  @Guide(description: "担当する話者ラベル。述べられていなければ「未定」。")
  var owner: String
  @Guide(description: "会議で述べられた期限。述べられていなければ「未定」。")
  var due: String
}

@available(iOS 26.0, *)
@Generable
private struct OverviewDigest {
  @Guide(description: "会議の内容が分かる見出し（30字以内）")
  var headline: String
  @Guide(description: "主な議題・結論・決定・今後の予定が分かる3〜5文の概要")
  var overview: String
  @Guide(description: "会議全体で重要なポイント。発言の書き写しではなく言い切りの文で。", .maximumCount(5))
  var keyPoints: [String]
}
