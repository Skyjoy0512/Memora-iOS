import Foundation

extension MemoraModel {
  func summarizeProjectSource(_ id: UUID, retry: Bool = false) async {
    guard var context = ProjectSourcePreparationContext(id, in: self), context.source.canProvideText,
          let reference = context.source.extractedTextReference,
          !projectSourceProcessingIDs.contains(id) else { return }
    if !retry, (context.source.summaryAttemptTextReference ?? context.source.summaryTextReference) == reference,
       context.source.summaryStatus != nil { return }
    let options = context.source.summaryOptions ?? SourceSummaryOptions()
    if let reason = sourceSummaryBlockedReason(id: id, options: options, includesBusyState: false) {
      context.source.summaryStatus = .unavailable
      context.source.summaryAttemptTextReference = reference
      context.source.summaryError = reason
      _ = storeProjectSource(context.source)
      return
    }
    guard let resolution = sourceSummaryResolution(for: options) else { return }
    let configuration = (engine: resolution.engine, llm: resolution.llm)
    let identity = summaryConfigurationIdentity
    let effective = AIEngineService.effectiveEngine(configuration.engine)
    let cloud = effective == .cloud || effective == .memora
    projectSourceProcessingIDs.insert(id)
    defer { projectSourceProcessingIDs.remove(id); recoverInterruptedProjectSources() }
    context.source.summaryStatus = .processing
    context.source.summaryAttemptTextReference = reference
    context.source.summaryError = nil
    guard storeProjectSource(context.source) else { return }
    do {
      let blocks = try await ProjectSourceTextReader.readAsync(reference)
      guard context.isCurrent(in: self), summaryConfigurationIdentity == identity,
            sourceSummaryResolution(for: options) == resolution else { return }
      guard blocks.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
        context.source.summaryStatus = .failed
        context.source.summaryError = "要約できる本文がありません。元の資料を確認してください。"
        _ = storeProjectSource(context.source)
        return
      }
      let timed = blocks.contains { $0.time != nil }
      let segments = blocks.map { block in
        TranscriptSegment(id: UUID(), speaker: block.page.map { "ページ\($0)" } ?? "原文",
          speakerIsCertain: false, timestamp: block.time ?? 0, text: block.text)
      }
      var input = MeetingSummaryInput(title: context.source.title, date: context.source.createdAt,
        duration: timed ? (blocks.compactMap(\.time).max() ?? 0) + 1 : 0,
        participantNames: [], transcript: segments, template: resolution.template,
        preferences: resolution.preferences)
      input.sourceContext = [context.source.originalURL?.absoluteString,
        context.source.textCoverage == .complete ? "抽出本文を参照。" : "一部の文字を参照。未取得部分を読んだと表現しない。",
        context.source.errorInformation].compactMap { $0 }.joined(separator: "\n")
      let snapshot = context
      let result = await MeetingSummarizer.summarize(input, engine: configuration.engine, llm: configuration.llm,
        authorize: { [weak self] in
          guard let self else { return false }
          return snapshot.isCurrent(in: self) && self.summaryConfigurationIdentity == identity &&
            self.sourceSummaryResolution(for: options) == resolution &&
            (!cloud || RecordAccessPolicy.allows(snapshot.source.privacy, purpose: .cloudAI))
        }, progress: { _ in })
      guard context.isCurrent(in: self), summaryConfigurationIdentity == identity,
            sourceSummaryResolution(for: options) == resolution else { return }
      switch result {
      case .success(let value):
        if let previous = context.source.summary, !previous.isEmpty, previous != value.markdown {
          context.source.summaryHistory = Array(((context.source.summaryHistory ?? []) + [previous]).suffix(3))
        }
        context.source.summary = value.markdown
        context.source.summaryTextReference = reference
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
