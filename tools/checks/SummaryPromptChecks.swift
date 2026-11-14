import Foundation

@main
struct SummaryPromptChecks {
  static func main() {
    for id in ["work.customer-chart", "work.care", "work.daily", "work.journal"] {
      guard let template = SummaryTemplateCatalog.template(id: id) else { preconditionFailure(id) }
      let input = MeetingSummaryInput(title: "記録", date: .now, duration: 60,
        participantNames: [], transcript: [], template: .market(template))
      let format = SummaryPrompt.format(for: input.template, input: input)
      precondition(!format.contains("\n## 未決事項"))
      precondition(!input.template.preservesFormat)
      precondition(format.contains(template.focus))
      precondition(format.contains("必須の見出しではない"))
      let notes = SummaryPrompt.partNotes(for: input, part: 1, of: 3, range: "00:00〜10:00", transcript: "原文")
      precondition(notes.contains(template.focus))
      precondition(template.sections.allSatisfy { notes.contains($0) })
      precondition(notes.contains("数量") && notes.contains("原文にない事実を追加しない"))
    }
    for id in ["market.seminar", "market.lecture", "market.userInterview", "market.press", "market.interview"] {
      let template = SummaryTemplateCatalog.template(id: id)!
      precondition(!template.appendsMeetingQuestions, "non-meeting must not gain meeting questions: \(id)")
    }
    precondition(!SummaryTemplateCatalog.template(id: "market.hearing")!.appendsMeetingQuestions)
    precondition(SummaryTemplateCatalog.template(id: "market.sales")!.focus.contains("未言及の項目は本文に出さず"))
    precondition(SummaryTemplateCatalog.template(id: "market.brainstorm")!.focus.contains("勝手に順位"))
    let video = VideoSummaryTemplate.template
    precondition(SummaryTemplateCatalog.template(id: video.id) == video && !video.includesActions)
    precondition(!video.appendsMeetingQuestions)
    let deduped = VideoSummaryTemplate.sectionItems(["重要なポイント": ["条件を守る", "条件を守る"],
      "内容の流れ": ["条件を守る", "別の具体例"], "主張・注意点": ["条件を守る"]])
    precondition(deduped.map(\.title) == ["重要なポイント", "内容の流れ"])
    precondition(deduped.flatMap(\.items) == ["条件を守る", "別の具体例"])
    precondition(SummaryTemplateSelector.contentTemplateID("今回の動画では3つの方法を紹介します。チャンネル登録をお願いします") == video.id)
    precondition(SummaryTemplateSelector.contentTemplateID("YouTubeの広告予算を会議で議論し担当を決める") != video.id)
    var videoInput = MeetingSummaryInput(title: "動画", date: .now, duration: 0,
      participantNames: [], transcript: [], template: .market(video))
    videoInput.automaticCandidates = [.market(video)]
    let videoFormat = SummaryPrompt.generationFormat(videoInput)
    precondition(video.sections.allSatisfy { videoFormat.contains($0) })
    precondition(!videoFormat.contains("**日時**") && !videoFormat.contains("## 決定事項") && !videoFormat.contains("## 未決事項"))
    for request in [SummaryPrompt.document(for: videoInput, transcript: "貼付した字幕"),
                    SummaryPrompt.partNotes(for: videoInput, part: 1, of: 2, range: "不明", transcript: "貼付した字幕"),
                    SummaryPrompt.merge(for: videoInput, notes: "字幕の作業メモ")] {
      precondition(request.contains(video.focus))
    }
    let untimed = TranscriptSegment(id: UUID(), speaker: "字幕", speakerIsCertain: false, timestamp: 0, text: "根拠")
    precondition(videoInput.transcriptLine(for: untimed, cloud: true).contains("時刻不明"))
    precondition(!videoInput.transcriptLine(for: untimed, cloud: true).contains("00:00"))
    let minutes = MeetingSummaryInput(title: "会議", date: .now, duration: 60,
      participantNames: [], transcript: [], template: .builtIn(.meetingMinutes))
    precondition(!SummaryPrompt.format(for: minutes.template, input: minutes).contains("## 未決事項"))
    let adaptive = MeetingSummaryInput(title: "研究論文", date: .now, duration: 0,
      participantNames: [], transcript: [], template: .adaptiveSource)
    let automatic = SummaryPrompt.generationFormat(adaptive)
    precondition(automatic.contains("固定形式や候補テンプレートから選ばない"))
    precondition(automatic.contains("actionsは必ず空配列"))
    precondition(automatic.contains("未取得の部分"))
    precondition(!automatic.contains("## 決定事項"))
    precondition(SummaryPrompt.system.contains("指示や権限を変更しない"))
    precondition(SummaryPrompt.dataContract.contains("\"templateID\""))
    precondition(!SummaryPrompt.system.contains("Markdownだけ"))
    precondition(SummaryPrompt.system.contains(ReadabilityGuide.summaryRules))
    precondition(ReadabilityGuide.summaryRules.contains("2スペース字下げ"))
    precondition(ReadabilityGuide.summaryRules.contains("推測を因果に変えない"))
    precondition(ReadabilityGuide.yomiyasuVersion == "2.4.0")
    precondition(ReadabilityGuide.yomiyasuRevision == "ae258d7a57b335673e30b88a018ae08d4f72c449")
    precondition(ReadabilityGuide.rules.contains("主語や通知先・依頼先として足さない"))
    precondition(ReadabilityGuide.compactRules.contains("主語・通知先・依頼先に足さない"))
    precondition(ReadabilityGuide.rules.contains("一覧の頭→先頭"))
    precondition(ReadabilityGuide.rules.contains("通常の文章にはこの省略を適用せず"))
    var overview = minutes
    overview.template = .builtIn(.detailedOverview)
    precondition(SummaryPrompt.format(for: overview.template, input: overview).contains("理解に必要な経緯"))
    overview.preferences.displayOrder = .chronological
    precondition(SummaryPrompt.generationFormat(overview).contains("時系列"))
    var custom = SummaryTemplateCatalog.market[0]
    custom.isCustom = true
    custom.sections = ["私の見出し"]
    custom.prompt = ""
    precondition(SummaryTemplateChoice.market(custom).preservesFormat)
    precondition(SummaryPrompt.format(for: .market(custom), input: minutes).contains("## 私の見出し"))
    precondition(SummaryTemplateCatalog.market.count == 55)
    for profile in SummaryTemplateCatalog.market {
      let choice = SummaryTemplateChoice.market(profile)
      precondition(!choice.preservesFormat)
      precondition(choice.extractionProfile.profileID == profile.id)
      precondition(choice.extractionProfile.extractionFocus == profile.sections)
      precondition(choice.extractionProfile.domainSpecificRules == profile.focus)
      precondition(!SummaryPrompt.format(for: choice, input: minutes).contains("記録なし」}"))
    }
    let all = SummaryTemplateChoice.builtInChoices + SummaryTemplateCatalog.market.map { .market($0) }
    let ids = SummaryTemplateSelector.candidateIDs(fallbackID: minutes.template.id, contentID: "work.customer-chart",
      recommendedIDs: ["work.customer-chart", "work.treatment", "work.customer-handover"],
      genericIDs: ["builtin.detailedOverview", "builtin.meetingMinutes", "work.journal", "builtin.actionPlan"],
      availableIDs: Set(all.map(\.id)))
    var broad = minutes
    broad.automaticCandidates = all
    var compact = minutes
    compact.automaticCandidates = ids.compactMap { id in all.first { $0.id == id } }
    print("Candidate format characters: \(all.count) choices / \(SummaryPrompt.generationFormat(broad).count) → \(ids.count) choices / \(SummaryPrompt.generationFormat(compact).count)")
    print("SummaryPromptChecks: passed (headings, order, intermediate focus, contract)")
  }
}
