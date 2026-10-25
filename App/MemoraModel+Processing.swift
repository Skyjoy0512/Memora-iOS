import Foundation

extension MemoraModel {
  /// Marks records whose processing was interrupted by a stop or a crash, so the
  /// screen shows a retry rather than a spinner.
  func recoverInterruptedJobs() {
    let ids = Set(processing.activeIDStrings.compactMap(UUID.init(uuidString:)))
    guard !ids.isEmpty else { return }
    // Older builds did not persist an attempt marker before sending. Treat
    // their interrupted requests conservatively rather than replaying them.
    var jobs = pendingSummaryJobs
    for index in jobs.indices where ids.contains(jobs[index].meetingID) {
      jobs[index].requiresUserRetry = true
    }
    if persistNow(jobs, forKey: StorageKey.pendingSummaryJobs) { pendingSummaryJobs = jobs }
    processing.restoreInterrupted([])
    persistInterruptedJobs()

    var changed = false
    for index in meetings.indices where ids.contains(meetings[index].id) {
      switch meetings[index].status {
      case .importing, .transcribing, .organizing:
        meetings[index].status = hasPendingSummary(meetings[index].id) && !meetings[index].transcript.isEmpty
          ? .waitingForSummary : .failed("処理が中断されました。音声は保存されています。もう一度試せます。")
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
    recoverCancelledSummaryRuns()
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
      enqueueAutomaticSummaryIfNeeded(for: id)
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
