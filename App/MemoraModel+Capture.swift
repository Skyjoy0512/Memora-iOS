import ActivityKit
import AVFAudio
import Foundation
import UIKit

extension MemoraModel {
  func handleRecorderInterruption(_ event: AudioRecorderService.Interruption) {
    guard isRecording else { return }

    switch event {
    case .began:
      realtimeTranscriber.stop()
      isRecordingPaused = true
      if recordingPausedAt == nil { recordingPausedAt = .now }
      recordingInterruptionMessage = "着信などでマイクが使えなくなり、録音を一時停止しました。「再開」で続けられます。"
    case .ended:
      if recordingInterruptionMessage == nil {
        recordingInterruptionMessage = "マイクが使えるようになりました。「再開」で録音を続けられます。"
      }
    case .inputLost(let reason):
      realtimeTranscriber.stop()
      isRecordingPaused = true
      if recordingPausedAt == nil { recordingPausedAt = .now }
      recordingInterruptionMessage = reason
    case .reset:
      realtimeTranscriber.stop()
      recordingInterruptionMessage = "オーディオがリセットされました。ここまでの録音を保存します。"
      Task { await stopCapture() }
    case .failed(let reason):
      realtimeTranscriber.stop()
      recordingInterruptionMessage = reason
      Task { await stopCapture() }
    }

    updateLiveActivity()
    refreshRecordingResources()
  }

  func startCapture(event: UpcomingMeeting? = nil, spaceID: UUID? = nil,
                    context suppliedContext: LocalImportContext? = nil) async {
    // A finished recording still waiting to be stored comes first: starting a new
    // one now could replace it, so save that one before recording anything else.
    guard !isRestoring else { return }
    guard !hasUnsavedRecording else {
      await retrySavingRecording()
      return
    }
    // Starting twice (a double tap, or two entry points) must not begin two
    // recordings, so a start already under way wins.
    guard !isPreparingCapture, !isSavingCapture else { return }
    guard !isRecording else {
      isCapturePresented = true
      return
    }

    guard let context = suppliedContext ?? LocalImportContext(projectID: spaceID, in: self),
          context.projectID == spaceID else {
      if !Task.isCancelled {
        recordingErrorMessage = "この保存先では録音できません。画面を開き直してください。"
      }
      return
    }
    guard validateCaptureContext(context) else { return }

    guard await resolvePendingRecordingBeforeCapture() else { return }
    guard !isRestoring, !isPreparingCapture, !isSavingCapture, !isRecording else { return }
    guard validateCaptureContext(context) else { return }

    isPreparingCapture = true
    guard spaceID == nil || ProjectFiling.existingProject(spaceID, in: spaces) != nil else {
      isPreparingCapture = false
      recordingErrorMessage = "保存先のプロジェクトが見つかりません。開き直してください。"
      return
    }
    let destinationID = spaceID ?? event.flatMap { recurringProjectID(forEventID: $0.id) }
    defer { isPreparingCapture = false }
    guard let destinationContext = LocalImportContext(projectID: destinationID, in: self) else { return }

    let allowed = await recorder.requestPermission()
    guard validateCaptureContext(context), validateCaptureContext(destinationContext) else { return }
    guard allowed else {
      microphonePermissionDenied = true
      announce("マイクの使用が許可されていません。設定から許可してください。")
      return
    }
    // The permission sheet can take a moment; re-check before starting.
    guard !isRecording, !isSavingCapture else { return }
    guard destinationID == nil || ProjectFiling.existingProject(destinationID, in: spaces) != nil else {
      recordingErrorMessage = "保存先のプロジェクトが削除されました。録音を開始する場所を選び直してください。"
      return
    }

    guard !Task.isCancelled else { return }
    let prepared: AudioRecorderService.PreparedRecording
    do {
      prepared = try recorder.prepareRecording()
    } catch {
      if !Task.isCancelled { recordingErrorMessage = error.localizedDescription }
      return
    }
    let recordingID = prepared.manifest.recordingID
    let fileName = prepared.manifest.parts[0].fileName
    // The manifest and draft are durable before the microphone receives a
    // sample, so a mid-recording rotation can be admitted against them.
    recordingURL = prepared.fileURL
    recordingStartedAt = .now
    recordingPausedAt = nil
    recordingPausedDuration = 0
    recordingElapsed = 0
    captureEvent = event
    recordingSpaceID = destinationID
    recordingTitle = event?.title ?? ""
    recordingNote = ""
    recordingMarkers = []
    isRecordingPaused = false
    recordingDraft = RecordingDraft(
      id: recordingID,
      fileName: fileName,
      title: event?.title ?? "",
      note: "",
      startedAt: .now,
      spaceID: destinationID,
      audioManifest: prepared.manifest
    )
    guard persistNow(recordingDraft, forKey: StorageKey.recordingDraft) else {
      recordingDraft = nil
      recordingURL = nil
      resetRecordingClock()
      recordingErrorMessage = "録音の復旧情報を保存できないため、開始を中止しました。ストレージの空き容量を確認してください。"
      return
    }
    let generation = aiWorkspaceGeneration
    let admit: @Sendable (RecordingRotation) async -> Bool = { [weak self] rotation in
      guard let self else { return false }
      return await self.admitRecordingRotation(rotation, generation: generation)
    }
    // The recording tap feeds live recognition as a secondary sink, so there is
    // one microphone tap. The live service drops input until it is prepared.
    let liveService = realtimeTranscriber
    let silenceWatch = VoiceActivitySilenceWatch()
    do {
      _ = try await recorder.startContinuous(prepared, admitRotation: admit,
        liveSink: { buffer in
          liveService.consume(buffer)
          silenceWatch.submit(buffer)
        })
      // Session ownership can suspend too. An obsolete request must not keep a
      // recording in the workspace that replaced it or retain its audio.
      guard validateCaptureContext(context), validateCaptureContext(destinationContext) else {
        recorder.cancelContinuous()
        recordingDraft = nil
        recordingURL = nil
        resetRecordingClock()
        try? RecordStore.remove(StorageKey.recordingDraft)
        if !MediaFiles.delete(prepared.fileURL) {
          deletionFailureMessage = "開始を取り消した録音ファイルを削除できませんでした。ストレージの空き容量を確認してください。"
        }
        return
      }
      recordingSilenceWatch = silenceWatch
      isRecording = true
      isCapturePresented = true
      levelMeter.reset()
      realtimeTranscriber.resetHistory()
      startRecordingTicker()
      startLiveActivity()
      refreshRecordingResources()
      announce("録音を開始しました")
    } catch {
      recordingDraft = nil
      recordingURL = nil
      resetRecordingClock()
      try? RecordStore.remove(StorageKey.recordingDraft)
      if !Task.isCancelled { recordingErrorMessage = error.localizedDescription }
    }
  }

  private func validateCaptureContext(_ context: LocalImportContext) -> Bool {
    guard context.isCurrent(in: self) else {
      if !Task.isCancelled {
        recordingErrorMessage = "保存先が変更されたため、録音を開始しませんでした。画面を開き直してお試しください。"
      }
      return false
    }
    return true
  }

  /// Stores a recording the last attempt could not. The record and draft are
  /// already in memory and on disk, so this only retries the write.
  func retrySavingRecording() async {
    guard hasUnsavedRecording, !isSavingCapture, !isRestoring, !isStoreProtected, !Task.isCancelled else { return }
    let draft = recordingDraft
    let workspaceGeneration = aiWorkspaceGeneration
    let navigationID = pendingMeetingNavigationID
    isSavingCapture = true
    defer { isSavingCapture = false }

    let committed = await commitRecordingSave()
    guard !Task.isCancelled, !isRestoring, !isStoreProtected, aiWorkspaceGeneration == workspaceGeneration,
          recordingDraft == draft, pendingMeetingNavigationID == navigationID else { return }
    guard committed else {
      persistenceFailureMessage = nil
      return
    }
    hasUnsavedRecording = false
    recordingDraft = nil
    let meetingID = pendingMeetingNavigationID
    if let meetingID {
      finishCaptureSave(meetingID: meetingID)
    }
  }

  /// The parts of finishing a capture that only run once the record is stored.
  func finishCaptureSave(meetingID: UUID) {
    if recordingSpaceID != nil, meeting(id: meetingID)?.spaceID == nil {
      projectFilingNotice = "録音中に保存先のプロジェクトが削除されたため、音声は未分類のファイルに保存しました。"
    }
    hasUnsavedRecording = false
    recordingInterruptionMessage = nil
    resetRecordingClock()
    recordingTitle = ""
    recordingNote = ""
    captureEvent = nil
    pendingMeetingNavigationID = meetingID
    isCapturePresented = false
    if let record = meeting(id: meetingID), case .transcribing = record.status {
      beginProcessing(meetingID)
      announce("録音を保存しました。文字起こしを準備しています。")
    } else {
      announce("録音の保存情報を保持しました。音声ファイルを確認してください。")
    }
    // Files handed over during the recording wait until now.
    Task { await processPendingImports() }
  }

  func completeCaptureDismissal() {
    // The sheet can be closed while recording continues, so remember what was
    // typed in case the app does not get to save.
    if isRecording, recordingDraft != nil {
      let draftID = recordingDraft?.id, url = recordingURL
      Task { [weak self] in
        guard let self, self.recordingDraft?.id == draftID, self.recordingURL == url else { return }
        let saved = await self.checkpointRecordingDraft()
        guard !saved, self.isRecording, self.recordingDraft?.id == draftID, self.recordingURL == url else { return }
        self.recordingErrorMessage = "録音のメモを保存できませんでした。入力内容は編集中のまま保持しています。空き容量を確認してから保存を再試行してください。"
      }
    }

    guard let meetingID = pendingMeetingNavigationID else {
      presentPendingSampleCleanupIfNeeded()
      return
    }
    pendingMeetingNavigationID = nil
    openSavedMeeting(meetingID)
    presentPendingSampleCleanupIfNeeded()
  }

  func cancelCapture() async {
    guard !isSavingCapture, !hasUnsavedRecording, !isPreparingCapture, !isRecoveringRecordingDraft, isStoreWritable() else { return }
    stopRecorder()
    var names = recordingDraft?.audioManifest?.fileNames ?? []
    if let name = recordingDraft?.fileName { names.append(name) }
    if let url = recordingURL, let name = MediaFiles.reference(for: url) { names.append(name) }
    let managed = Set(names.compactMap { name -> String? in
      guard let url = MediaFiles.resolve(name) else { return nil }
      return MediaFiles.reference(for: url)
    })
    let additions = managed.map { PendingMediaDeletion(id: UUID(), audioReference: $0, photoNames: []) }
    let pending = pendingMediaDeletions + additions
    guard persistBatch({
      [(key: StorageKey.pendingMediaDeletions, data: try RecordStore.encoded(pending))]
    }, removing: [StorageKey.recordingDraft]) else {
      recordingErrorMessage = "録音の破棄を保存できませんでした。元のファイルと下書きは変更していません。空き容量を確認してください。"
      await endLiveActivity()
      return
    }
    recordingDraft = nil
    pendingMediaDeletions = pending
    retryPendingMediaDeletions(onlyIDs: Set(additions.map(\.id)))
    isCapturePresented = false
    captureEvent = nil
    recordingInterruptionMessage = nil
    resetRecordingClock()
    await endLiveActivity()
  }

  /// Stops the microphone, the live transcript and both tickers. Shared by
  /// saving and discarding, which differ only in what happens to the audio.
  func stopRecorder() {
    realtimeTranscriber.stop()
    recorder.cancelContinuous()
    recordingTicker?.cancel()
    recordingTicker = nil
    levelTicker?.cancel()
    levelTicker = nil
    recordingSilenceTicker?.cancel()
    recordingSilenceTicker = nil
    recordingSilenceWatch?.setEnabled(false)
    recordingSilenceWatch = nil
    isRecordingQuiet = false
    levelMeter.reset()
    isRecording = false
    isRecordingPaused = false
  }

  /// Forgets the finished recording's file and timing.
  private func resetRecordingClock() {
    recordingMarkers = []
    recordingSpaceID = nil
    recordingURL = nil
    recordingStartedAt = nil
    recordingPausedAt = nil
    recordingPausedDuration = 0
  }

  func toggleCapturePause() {
    guard isRecording else { return }
    if isRecordingPaused {
      guard recorder.resume() else {
        recordingInterruptionMessage = recorder.lastFailureReason
          ?? "録音を再開できませんでした。「再開」で再試行するか、ここまでの録音を保存してください。"
        updateLiveActivity()
        refreshRecordingResources()
        return
      }
      if let recordingPausedAt {
        recordingPausedDuration += Date.now.timeIntervalSince(recordingPausedAt)
      }
      self.recordingPausedAt = nil
      isRecordingPaused = false
      recordingInterruptionMessage = nil
      // Resource policy below decides whether live recognition should resume.
    } else {
      realtimeTranscriber.stop()
      recorder.pause()
      recordingPausedAt = .now
      isRecordingPaused = true
    }
    updateLiveActivity()
    refreshRecordingResources()
  }

  func startRecordingTicker() {
    recordingTicker?.cancel()
    recordingTicker = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled, let self, self.isRecording else { return }
        if let duration = self.recorder.recordedDuration {
          if self.recordingElapsed != duration { self.recordingElapsed = duration }
        }
      }
    }
  }

  var recordingStatusMessage: String? {
    recordingInterruptionMessage ?? (isRecordingQuiet ? Self.recordingQuietMessage : nil)
  }

  private static let recordingQuietMessage = "発話が90秒間検出されませんでした。録音を終えるには停止を押してください。"

  func startSilenceTicker() {
    guard let watch = recordingSilenceWatch else { return }
    recordingSilenceTicker = Task { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(2)) } catch { return }
        let quiet = await watch.evaluate()
        guard !Task.isCancelled, let self, self.recordingSilenceWatch === watch else { return }
        guard let quiet, quiet != self.isRecordingQuiet else { continue }
        self.isRecordingQuiet = quiet
        if quiet { self.announce(Self.recordingQuietMessage) }
      }
    }
  }

  /// Created only while a visible, active meter needs samples.
  func startLevelTicker() {
    levelTicker?.cancel()
    levelTicker = Task { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        guard !Task.isCancelled, let self, self.isRecording, !self.isRecordingPaused,
              self.levelMeter.isActive, self.recordingIsForeground else { return }
        self.levelMeter.update(from: self.recorder.level())
      }
    }
  }

  private func startLiveActivity() {
    guard ActivityAuthorizationInfo().areActivitiesEnabled,
          let startedAt = recordingStartedAt else { return }
    let attributes = MemoraRecordingAttributes(title: "Memoraで録音中")
    let state = MemoraRecordingAttributes.ContentState(startedAt: startedAt, isPaused: false)
    let content = ActivityContent(state: state, staleDate: nil)
    recordingActivity = try? Activity.request(attributes: attributes, content: content)
  }

  /// Anchors the state to the real elapsed time, so the live timer matches the
  /// screen and a pause freezes the number instead of counting on.
  private func updateLiveActivity() {
    guard let recordingActivity else { return }
    let elapsed = recordingElapsed
    let state = MemoraRecordingAttributes.ContentState(
      startedAt: Date.now.addingTimeInterval(-elapsed),
      isPaused: isRecordingPaused,
      pausedElapsed: elapsed
    )
    let content = ActivityContent(state: state, staleDate: nil)
    Task {
      await recordingActivity.update(content)
    }
  }

  func endLiveActivity() async {
    guard let recordingActivity else { return }
    let state = MemoraRecordingAttributes.ContentState(
      startedAt: recordingStartedAt ?? .now,
      isPaused: false,
      pausedElapsed: recordingElapsed
    )
    let content = ActivityContent(state: state, staleDate: nil)
    await recordingActivity.end(content, dismissalPolicy: .immediate)
    self.recordingActivity = nil
  }

  /// Ends any activity left over from a previous run. Recording never resumes on
  /// its own, so a stale one would only show the wrong thing.
  func endStaleLiveActivities() async {
    for activity in Activity<MemoraRecordingAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }
}
