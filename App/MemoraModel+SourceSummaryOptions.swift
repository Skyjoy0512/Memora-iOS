import Foundation

extension MemoraModel {
  func sourceSummaryOptions(for id: UUID) -> SourceSummaryOptions {
    source(id: id)?.summaryOptions ?? SourceSummaryOptions()
  }

  func sourceSummaryConfiguration(for options: SourceSummaryOptions) -> (engine: AIEngine, llm: LLMSelection)? {
    guard options.isValid else { return nil }
    guard let choice = options.engineChoice else { return askAIConfiguration }
    switch choice {
    case .settings: return settingsAIConfiguration
    case .onDevice: return (.foundation, aiSelection)
    case .registered(let id):
      guard let registered = registeredLLMs.models.first(where: { $0.id == id }) else { return nil }
      return (.cloud, registered.selection)
    }
  }

  func sourceSummaryTemplate(for options: SourceSummaryOptions) -> SummaryTemplateChoice? {
    guard options.isValid else { return nil }
    guard let id = options.templateID, id != SummaryTemplateChoice.adaptive.id else { return .adaptiveSource }
    return summaryChoice(id)
  }

  func sourceSummaryResolution(for options: SourceSummaryOptions) -> SourceSummaryResolution? {
    guard let template = sourceSummaryTemplate(for: options), let configuration = sourceSummaryConfiguration(for: options) else { return nil }
    var preferences = summaryPreferences
    if let length = options.length { preferences.length = length }
    if case .market(let market) = template, !market.supportedSummaryLengths.contains(preferences.length) { return nil }
    return .init(template: template, preferences: preferences, engine: configuration.engine, llm: configuration.llm)
  }

  func sourceSummaryUnavailableReason(id: UUID, options: SourceSummaryOptions) -> String? {
    sourceSummaryBlockedReason(id: id, options: options, includesBusyState: true)
  }

  func sourceSummaryBlockedReason(id: UUID, options: SourceSummaryOptions, includesBusyState: Bool) -> String? {
    if Task.isCancelled { return "操作が中断されました。もう一度開いてお試しください。" }
    if isRestoring { return "復元が終わってからお試しください。" }
    if isStoreProtected { return "保存先を利用できません。復旧後にお試しください。" }
    if currentTeamID != nil { return "このワークスペースでは資料を変更できません。" }
    guard let source = source(id: id) else { return "資料が見つかりません。" }
    if source.projectID.map({ space(id: $0) == nil }) == true { return "資料の保存先が見つかりません。" }
    guard source.canProvideText, source.extractedTextReference != nil else { return "要約できる本文がありません。資料を読み取ってからお試しください。" }
    if includesBusyState && (projectSourceProcessingIDs.contains(id) || sourcePreparationJobs[id] != nil) {
      return "資料を準備しています。完了してからお試しください。"
    }
    guard options.isValid else { return "要約の設定を選び直してください。" }
    guard let template = sourceSummaryTemplate(for: options) else { return "選んだテンプレートは削除されています。別の形式を選んでください。" }
    guard let configuration = sourceSummaryConfiguration(for: options) else { return "選んだAIモデルは削除されています。別のモデルを選んでください。" }
    if case .market(let market) = template,
       !market.supportedSummaryLengths.contains(options.length ?? summaryPreferences.length) {
      return "このテンプレートに対応する長さを選んでください。"
    }
    let engine = AIEngineService.effectiveEngine(configuration.engine)
    if (engine == .cloud || engine == .memora), !RecordAccessPolicy.allows(source.privacy, purpose: .cloudAI) {
      return "クラウドAIへの送信が許可されていません。資料のプライバシーを確認するか、端末内AIを選んでください。"
    }
    return nil
  }

  @discardableResult
  func startProjectSourceSummary(_ id: UUID, options: SourceSummaryOptions,
                                 expectedSource: ProjectSource, configurationIdentity: [UUID]) -> Bool {
    guard expectedSource.id == id, source(id: id) == expectedSource,
          summaryConfigurationIdentity == configurationIdentity,
          sourceSummaryUnavailableReason(id: id, options: options) == nil,
          let resolution = sourceSummaryResolution(for: options),
          let context = ProjectSourcePreparationContext(id, in: self) else { return false }
    var candidate = context.source
    candidate.summaryOptions = options
    candidate.summaryStatus = .processing
    candidate.summaryAttemptTextReference = candidate.extractedTextReference
    candidate.summaryError = nil
    guard storeProjectSource(candidate) else { return false }
    let submittedSource = candidate
    let attempt = UUID()
    let generation = aiWorkspaceGeneration
    let task = Task { [weak self] in
      guard let self else { return }
      defer {
        if self.sourcePreparationJobs[id]?.id == attempt { self.sourcePreparationJobs.removeValue(forKey: id) }
        self.recoverInterruptedProjectSources(includingPending: true)
      }
      guard !Task.isCancelled, self.aiWorkspaceGeneration == generation,
            self.source(id: id) == submittedSource, self.summaryConfigurationIdentity == configurationIdentity,
            self.sourceSummaryResolution(for: options) == resolution else { return }
      await self.summarizeProjectSource(id, retry: true)
    }
    sourcePreparationJobs[id] = (attempt, task)
    return true
  }
}
