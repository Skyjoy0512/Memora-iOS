import Foundation

extension MemoraModel {
  func summarizeProjectSource(_ id: UUID, retry: Bool = false) async {
    guard var context = ProjectSourcePreparationContext(id, in: self), context.source.canProvideText,
          let reference = context.source.extractedTextReference,
          !projectSourceProcessingIDs.contains(id) else { return }
    if !retry, context.source.summaryTextReference == reference, context.source.summaryStatus != nil { return }
    let configuration = askAIConfiguration
    let identity = summaryConfigurationIdentity
    let effective = AIEngineService.effectiveEngine(configuration.engine)
    let cloud = effective == .cloud || effective == .memora
    if cloud, !RecordAccessPolicy.allows(context.source.privacy, purpose: .cloudAI) {
      context.source.summaryStatus = .unavailable
      context.source.summaryError = "本文は保存しました。要約するには資料のプライバシーでクラウドAIへの送信を許可するか、端末内AIを選んで再試行してください。"
      _ = storeProjectSource(context.source)
      return
    }
    projectSourceProcessingIDs.insert(id)
    defer { projectSourceProcessingIDs.remove(id); recoverInterruptedProjectSources() }
    context.source.summaryStatus = .processing
    context.source.summaryTextReference = reference
    context.source.summaryError = nil
    guard storeProjectSource(context.source) else { return }
    do {
      let blocks = try await ProjectSourceTextReader.readAsync(reference)
      guard context.isCurrent(in: self), !blocks.isEmpty else { return }
      let timed = blocks.contains { $0.time != nil }
      let segments = blocks.map { block in
        TranscriptSegment(id: UUID(), speaker: block.page.map { "ページ\($0)" } ?? "原文",
          speakerIsCertain: false, timestamp: block.time ?? 0, text: block.text)
      }
      var input = MeetingSummaryInput(title: context.source.title, date: context.source.createdAt,
        duration: timed ? (blocks.compactMap(\.time).max() ?? 0) + 1 : 0,
        participantNames: [], transcript: segments, template: .adaptiveSource,
        preferences: summaryPreferences)
      input.sourceContext = [context.source.originalURL?.absoluteString,
        context.source.textCoverage == .complete ? "抽出本文を参照。" : "一部の文字を参照。未取得部分を読んだと表現しない。",
        context.source.errorInformation].compactMap { $0 }.joined(separator: "\n")
      let snapshot = context
      let result = await MeetingSummarizer.summarize(input, engine: configuration.engine, llm: configuration.llm,
        authorize: { [weak self] in
          guard let self else { return false }
          return snapshot.isCurrent(in: self) && self.summaryConfigurationIdentity == identity &&
            (!cloud || RecordAccessPolicy.allows(snapshot.source.privacy, purpose: .cloudAI))
        }, progress: { _ in })
      guard context.isCurrent(in: self), summaryConfigurationIdentity == identity else { return }
      switch result {
      case .success(let value):
        if let previous = context.source.summary, !previous.isEmpty, previous != value.markdown {
          context.source.summaryHistory = Array(((context.source.summaryHistory ?? []) + [previous]).suffix(3))
        }
        context.source.summary = value.markdown
        context.source.summaryStatus = .ready
        context.source.summaryUpdatedAt = .now
        context.source.summaryError = nil
      case .failure(let failure):
        context.source.summaryStatus = .failed
        context.source.summaryError = failure.message
      }
      _ = storeProjectSource(context.source)
    } catch {
      guard context.isCurrent(in: self, allowsCancellation: true) else { return }
      context.source.summaryStatus = .failed
      context.source.summaryError = "要約できませんでした。原文は保存されています。再試行できます。"
      _ = storeProjectSource(context.source)
    }
  }
}
