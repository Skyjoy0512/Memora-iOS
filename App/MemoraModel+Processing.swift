import Foundation

extension MemoraModel {
  /// Marks records whose processing was interrupted by a stop or a crash, so the
  /// screen shows a retry rather than a spinner.
  func recoverInterruptedJobs() {
    let ids = Set(processing.activeIDStrings.compactMap(UUID.init(uuidString:)))
    guard !ids.isEmpty else { return }
    processing.restoreInterrupted([])
    persistInterruptedJobs()

    var changed = false
    for index in meetings.indices where ids.contains(meetings[index].id) {
      switch meetings[index].status {
      case .importing, .transcribing, .organizing:
        meetings[index].status = .failed("処理が中断されました。音声は保存されています。もう一度試せます。")
        changed = true
      default:
        break
      }
    }
    if changed {
      persistMeetings()
    }
  }

  func persistInterruptedJobs() {
    persistInBackground(processing.activeIDStrings, forKey: StorageKey.activeJobs)
  }

  func retryProcessing(_ id: UUID) {
    updateMeeting(id) { meeting in
      meeting.status = .transcribing(0.08)
    }
    beginProcessing(id)
  }

  /// Starts transcription for any record that has audio and is not already being
  /// processed: an imported file and a recovered recording take the same path.
  func startTranscription(_ id: UUID) {
    guard let meeting = meeting(id: id),
          meeting.audioURL != nil,
          !processing.isActive(id), !speakerAnalysisIDs.contains(id), !isRestoring, isStoreWritable() else { return }
    updateMeeting(id) { $0.status = .transcribing(0.08) }
    runTranscription(id, preparation: .milliseconds(600), progress: 0.62, recordsTiming: false)
  }

  /// Rewrites the summary from the real transcript with the chosen template,
  /// then files its decisions, open questions and key points on the record and
  /// its actions in the tasks tab. Nothing is invented: when no engine can
  /// answer, the record says so and keeps whatever the person had.
  ///
  /// `configuration` is the AI chosen in the summary sheet; without one, the
  /// settings engine is used.
  func generateSummary(
    _ id: UUID,
    choice: SummaryTemplateChoice,
    configuration: (engine: AIEngine, llm: LLMSelection)? = nil,
    automaticallySelect: Bool = false,
    useCaseID: String? = nil,
    preferences: SummaryPreferences? = nil,
    cloudDisclosureConfirmed: Bool = false
  ) {
    guard let meeting = meeting(id: id), !meeting.transcript.isEmpty,
          !speakerAnalysisIDs.contains(id), !processing.isActive(id), !isRestoring, isStoreWritable() else { return }
    let selectedEngine = configuration?.engine ?? settingsAIConfiguration.engine
    let effectiveEngine = AIEngineService.effectiveEngine(selectedEngine)
    let usesCloud = effectiveEngine == .cloud || effectiveEngine == .memora
    if effectiveEngine == .cloud || effectiveEngine == .memora {
      guard RecordAccessPolicy.allows(meeting.effectivePrivacy, purpose: .cloudAI,
        explicitCloudConsent: cloudDisclosureConfirmed) else {
        announce(RecordAccessPolicy.refusal)
        return
      }
    }

    updateMeeting(id) { $0.status = .organizing(choice.processingLabel) }
    let inputRevision = ProcessingService.inputRevision(meeting.transcript)
    let summaryRevision = meeting.summary
    let startedAt = Date()
    let input = MeetingSummaryInput(
      title: meeting.displayTitle,
      date: meeting.createdAt,
      duration: meeting.duration,
      participantNames: usesCloud ? [] : (meeting.participantIDs ?? []).compactMap { person(id: $0)?.name },
      transcript: meeting.transcript,
      template: choice,
      glossary: processingVocabulary(external: usesCloud),
      preferences: preferences ?? summaryPreferences,
      automaticCandidates: automaticallySelect ? automaticSummaryCandidates(for: meeting, fallback: choice) : []
    )
    let engine = configuration?.engine ?? settingsAIConfiguration.engine
    let llm = configuration?.llm ?? settingsAIConfiguration.llm

    processing.run(id: id) { [weak self] in
      let background = BackgroundActivity(name: "要約を作成")
      defer { background.end() }
      return await MeetingSummarizer.summarize(input, engine: engine, llm: llm) { step in
        guard let self, !Task.isCancelled else { return }
        self.updateMeetingTransiently(id) { meeting in
          if case .organizing = meeting.status {
            meeting.status = .organizing("\(choice.processingLabel)：\(step)")
          }
        }
      }
    } apply: { [weak self] result in
      guard let self, !Task.isCancelled else { return }
      self.performance.record(
        "処理（要約）",
        milliseconds: Date.now.timeIntervalSince(startedAt) * 1_000
      )

      // The service checks the run; these two fingerprints catch an edit made
      // while the answer was being written. A transcript that changed or a
      // summary that was edited by hand wins over the older result.
      guard let current = self.meeting(id: id) else { return }
      guard !self.isRestoring, self.isStoreWritable() else { return }
      guard current.privacy == meeting.privacy else {
        self.updateMeeting(id) { $0.status = .waitingForSummary }
        self.announce("外部送信の設定が変わったため、古い要約は反映しませんでした。")
        return
      }
      let transcriptChanged = ProcessingService.inputRevision(current.transcript) != inputRevision
      let summaryEdited = current.summary != summaryRevision
      guard !transcriptChanged, !summaryEdited else {
        self.updateMeeting(id) { $0.status = .waitingForSummary }
        self.announce("記録が編集されたため、古い要約は反映しませんでした。もう一度生成できます。")
        return
      }

      switch result {
      case .success(let summary):
        self.updateMeeting(id) { meeting in
          if !meeting.summary.isEmpty, !meeting.summaryVersions.contains(where: { $0.markdown == meeting.summary }) {
            meeting.summaryVersions.append(.snapshot(record: meeting, templateID: nil,
              preferences: input.preferences, modelInfo: "手動編集・旧形式"))
          }
          meeting.summary = summary.markdown
          meeting.keyPoints = summary.keyPoints
          meeting.decisions = summary.decisions
          meeting.openQuestions = summary.openQuestions
          meeting.status = .ready
          if let useCaseID { meeting.summaryUseCaseID = useCaseID.isEmpty ? nil : useCaseID }
          let version = TemplateSummary.snapshot(record: meeting, templateID: summary.templateID,
            preferences: input.preferences, modelInfo: engine == .cloud || engine == .memora ? llm.modelLabel : "端末内AI",
            evidence: summary.evidence)
          meeting.summaryVersions.append(version)
          meeting.activeSummaryVersionID = version.id
          meeting.privacy = meeting.effectivePrivacy
          if input.automaticCandidates.isEmpty, case .market(let template) = input.template {
            meeting.privacy.protect(template.sensitivityClassification)
          }
          if let selected = summary.templateID.flatMap(self.summaryChoice), case .market(let template) = selected {
            meeting.privacy.protect(template.sensitivityClassification)
          }
        }
        let added = self.addExtractedTasks(summary.actions, meetingID: id, meetingDate: current.createdAt)
        let permitsAutomaticDelivery = self.allowsRecordAccess(id, purpose: .automaticWebhook)
        if permitsAutomaticDelivery { self.deliverSummaryToWebhooks(id) }
        self.runResidentsAfterMeeting(id)
        self.offerPlusIfNeeded()
        self.announce(added > 0 ? "要約ができました。タスクを\(added)件追加しました。" : "要約ができました。")
      case .failure(.cancelled):
        // Cancelled without a newer request taking over: leave the record able
        // to be generated again rather than stuck mid-process.
        self.updateMeeting(id) { meeting in
          if case .organizing = meeting.status {
            meeting.status = .waitingForSummary
          }
        }
      case .failure(let failure):
        let message = failure == .empty ? "要約が空でした。もう一度お試しください。" : failure.message
        self.updateMeeting(id) { $0.status = .failed(message) }
        self.announce("要約を作成できませんでした。\(message)")
      }
    }
  }

  func beginProcessing(_ id: UUID) {
    runTranscription(id, preparation: .milliseconds(700), progress: 0.58, recordsTiming: true)
  }

  /// The one transcription job both entry points share. They differ only in how
  /// long the preparation pause is, where the progress bar lands after it, and
  /// whether the run counts toward the performance log.
  private func runTranscription(
    _ id: UUID,
    preparation: Duration,
    progress: Double,
    recordsTiming: Bool
  ) {
    guard !isRestoring, isStoreWritable(), !speakerAnalysisIDs.contains(id),
          let original = meeting(id: id) else { return }
    let revision = ProcessingService.inputRevision(original.transcript)
    processing.run(id: id) { [weak self] in
      guard let self else { return TranscriptionOutcome.unavailable }
      // Checked before the job starts, so a missing key or an unsupported
      // language is reported at once instead of after a spinner.
      let availability = await EngineAvailability.transcription(
        EngineAvailability.currentTranscriptionEngine(),
        language: EngineAvailability.currentTranscriptionLanguage(),
        provider: EngineAvailability.currentTranscriptionProvider()
      )
      guard availability.isReady else {
        return .failed(availability.message ?? "文字起こしを開始できませんでした。")
      }
      let startedAt = Date()
      defer {
        if recordsTiming {
          self.performance.record(
            "処理（文字起こし）",
            milliseconds: Date.now.timeIntervalSince(startedAt) * 1_000
          )
        }
      }
      try? await Task.sleep(for: preparation)
      guard !Task.isCancelled else { return .unavailable }
      self.updateMeeting(id) { $0.status = .transcribing(progress) }

      // Only a real engine's transcript is ever stored. When none can run, the
      // record says so and keeps the audio for a retry — never sample text.
      return await TranscriptionService.transcribe(
        fileURL: original.audioURL,
        vocabulary: self.transcriptionVocabulary,
        cloudVocabulary: self.processingVocabulary(external: true)
      )
    } apply: { [weak self] outcome in
      guard let self, !Task.isCancelled, !self.isRestoring, self.isStoreWritable(),
            let current = self.meeting(id: id) else { return }
      guard current.audioURL == original.audioURL,
            ProcessingService.inputRevision(current.transcript) == revision else {
        self.updateMeeting(id) { $0.status = $0.transcript.isEmpty ? .waitingForTranscription : .waitingForSummary }
        self.announce("記録が編集されたため、古い文字起こしは反映しませんでした。原音声・原文は保持しています。")
        return
      }
      self.applyTranscription(outcome, to: id)
    }
  }

  private func applyTranscription(_ outcome: TranscriptionOutcome, to id: UUID) {
    switch outcome {
    case .segments(let segments):
      updateMeeting(id) { meeting in
        meeting.transcript = segments
        meeting.status = .waitingForSummary
      }
      announce("文字起こしができました。要約を作成しています。")
      if automaticallyAnalyzesSpeakers, SpeakerModelAssets.isInstalled {
        Task { [weak self] in
          guard let self, self.automaticallyAnalyzesSpeakers else { return }
          await self.analyzeSpeakers(id)
        }
      }
    case .unavailable:
      updateMeeting(id) {
        $0.status = .failed("この端末では文字起こしを利用できません。音声は保存されています。設定で別のエンジンを選ぶか、別の端末でお試しください。")
      }
      announce("文字起こしができませんでした。音声は保存されています。")
    case .failed(let message):
      updateMeeting(id) { $0.status = .failed(message) }
      announce("文字起こしができませんでした。\(message)")
    case .nothingRecognized:
      updateMeeting(id) {
        $0.status = .failed("音声から発言を認識できませんでした。音声は保存されています。もう一度お試しください。")
      }
      announce("音声から発言を認識できませんでした。")
    case .cancelled:
      // Nothing was applied: the record goes back to where it can be started
      // again, rather than being left looking stuck.
      updateMeeting(id) { meeting in
        if case .transcribing = meeting.status {
          meeting.status = .waitingForTranscription
        }
      }
    }
  }
}
