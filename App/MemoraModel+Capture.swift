import ActivityKit
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
  }

  func startCapture(event: UpcomingMeeting? = nil, spaceID: UUID? = nil) async {
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

    isPreparingCapture = true
    guard spaceID == nil || ProjectFiling.existingProject(spaceID, in: spaces) != nil else {
      isPreparingCapture = false
      recordingErrorMessage = "保存先のプロジェクトが見つかりません。開き直してください。"
      return
    }
    let destinationID = spaceID ?? event.flatMap { recurringProjectID(forEventID: $0.id) }
    defer { isPreparingCapture = false }

    let allowed = await recorder.requestPermission()
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

    do {
      recordingURL = try await recorder.start()
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
      isRecording = true
      isCapturePresented = true
      levelMeter.reset()
      if let recordingURL, let fileName = MediaFiles.reference(for: recordingURL) {
        recordingDraft = RecordingDraft(
          id: UUID(),
          fileName: fileName,
          title: event?.title ?? "",
          note: "",
          startedAt: .now,
          spaceID: destinationID
        )
        guard persistNow(recordingDraft, forKey: StorageKey.recordingDraft) else {
          stopRecorder()
          isCapturePresented = false
          recordingDraft = nil
          _ = MediaFiles.delete(recordingURL)
          resetRecordingClock()
          recordingErrorMessage = "録音の復旧情報を保存できないため、開始を中止しました。ストレージの空き容量を確認してください。"
          return
        }
      }
      startRecordingTicker()
      startLevelTicker()
      startLiveActivity()
      realtimeTranscriber.start()
      announce("録音を開始しました")
    } catch {
      recordingErrorMessage = error.localizedDescription
    }
  }

  func stopCapture() async {
    guard isRecording, !isSavingCapture else { return }
    isSavingCapture = true
    let startedAt = Date()
    defer {
      isSavingCapture = false
      performance.record(
        "保存（録音の確定）",
        milliseconds: Date.now.timeIntervalSince(startedAt) * 1_000
      )
    }

    let measuredDuration = recorder.recordedDuration ?? recordingElapsed
    stopRecorder()
    await endLiveActivity()
    let finalDuration = if let recordingURL {
      await MediaFiles.duration(of: recordingURL) ?? measuredDuration
    } else {
      measuredDuration
    }

    var meeting = Meeting(
      id: recordingDraft?.id ?? UUID(),
      title: recordingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? "新しい会話"
        : recordingTitle.trimmingCharacters(in: .whitespacesAndNewlines),
      createdAt: recordingStartedAt ?? .now,
      duration: max(finalDuration, 1),
      source: .recording,
      status: .transcribing(0.12),
      summary: "録音を保存しました。文字起こしを準備しています。",
      keyPoints: [],
      decisions: [],
      openQuestions: [],
      transcript: [],
      spaceID: ProjectFiling.existingProject(recordingSpaceID, in: spaces),
      audioURL: recordingURL
    )
    meeting.notes = recordingNote
    meeting.recordingMarkers = RecordingMarker.validated(recordingMarkers, duration: meeting.duration)
    meeting.calendarEventID = captureEvent?.id
    captureEvent = nil
    meetings.insert(meeting, at: 0)
    lifeLogEntries.insert(
      LifeLogEntry(
        id: meeting.id,
        createdAt: meeting.createdAt,
        title: meeting.title,
        summary: "iPhoneで新しい音声を記録しました。",
        source: .iphone,
        meetingID: meeting.id
      ),
      at: 0
    )
    // The record, its journal entry and the draft removal are one commit: the
    // draft is only gone once the record is stored, so a failure or a stop here
    // leaves the audio recoverable rather than lost. On failure the draft stays
    // and the next launch rebuilds the record from it (with the same id), so no
    // duplicate is made.
    let committed = await commitRecordingSave()
    guard committed else {
      // Do not take the success path: keep the title, note, audio and draft so
      // the recording can be saved again, and refuse to start another one until
      // it is. The generic save alert is replaced by the recording one.
      persistenceFailureMessage = nil
      hasUnsavedRecording = true
      isUnsavedRecordingAlertPresented = true
      pendingMeetingNavigationID = meeting.id
      isCapturePresented = false
      return
    }
    recordingDraft = nil
    noteRealSaveForSampleCleanup()
    finishCaptureSave(meetingID: meeting.id)
  }

  /// Stores a recording the last attempt could not. The record and draft are
  /// already in memory and on disk, so this only retries the write.
  func retrySavingRecording() async {
    guard hasUnsavedRecording, !isSavingCapture else { return }
    isSavingCapture = true
    defer { isSavingCapture = false }

    let committed = await commitRecordingSave()
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
  private func finishCaptureSave(meetingID: UUID) {
    if recordingSpaceID != nil, meeting(id: meetingID)?.spaceID == nil {
      projectFilingNotice = "録音中に保存先のプロジェクトが削除されたため、音声は未分類のファイルに保存しました。"
    }
    hasUnsavedRecording = false
    recordingInterruptionMessage = nil
    resetRecordingClock()
    recordingTitle = ""
    recordingNote = ""
    captureEvent = nil
    selectedTab = .files
    pendingMeetingNavigationID = meetingID
    isCapturePresented = false
    beginProcessing(meetingID)
    announce("録音を保存しました。文字起こしを準備しています。")
    // Files handed over during the recording wait until now.
    Task { await processPendingImports() }
  }

  func completeCaptureDismissal() {
    // The sheet can be closed while recording continues, so remember what was
    // typed in case the app does not get to save.
    if isRecording, recordingDraft != nil {
      recordingDraft?.title = recordingTitle
      recordingDraft?.note = recordingNote
      persistRecordingDraft()
    }

    guard let meetingID = pendingMeetingNavigationID else {
      presentPendingSampleCleanupIfNeeded()
      return
    }
    pendingMeetingNavigationID = nil
    selectedTab = .files
    if let spaceID = meeting(id: meetingID)?.spaceID, space(id: spaceID) != nil {
      libraryPath = [.space(spaceID), .meeting(meetingID)]
    } else {
      libraryPath = [.meeting(meetingID)]
    }
    presentPendingSampleCleanupIfNeeded()
  }

  func cancelCapture() async {
    stopRecorder()
    isCapturePresented = false
    // Discarding means the audio goes too; nothing is kept for the journal.
    captureEvent = nil
    recordingDraft = nil
    persistRecordingDraft()
    recordingInterruptionMessage = nil
    if !MediaFiles.delete(recordingURL) {
      deletionFailureMessage = "録音ファイルを削除できませんでした。ストレージの空き容量を確認してください。"
    }
    resetRecordingClock()
    await endLiveActivity()
  }

  /// Stops the microphone, the live transcript and both tickers. Shared by
  /// saving and discarding, which differ only in what happens to the audio.
  private func stopRecorder() {
    realtimeTranscriber.stop()
    recorder.stop()
    recordingTicker?.cancel()
    recordingTicker = nil
    levelTicker?.cancel()
    levelTicker = nil
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
        recordingErrorMessage = "録音を再開できませんでした。"
        return
      }
      if let recordingPausedAt {
        recordingPausedDuration += Date.now.timeIntervalSince(recordingPausedAt)
      }
      self.recordingPausedAt = nil
      isRecordingPaused = false
      recordingInterruptionMessage = nil
      realtimeTranscriber.start()
    } else {
      realtimeTranscriber.stop()
      recorder.pause()
      recordingPausedAt = .now
      isRecordingPaused = true
    }
    updateLiveActivity()
  }

  private func startRecordingTicker() {
    recordingTicker?.cancel()
    recordingTicker = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled, let self, self.isRecording else { return }
        if let duration = self.recorder.recordedDuration {
          self.recordingElapsed = duration
        }
      }
    }
  }

  /// Samples the recorder at ~22Hz so the glow can follow the voice.
  private func startLevelTicker() {
    levelTicker?.cancel()
    levelTicker = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(45))
        guard let self else { return }
        // Nothing shows the glow unless a screen asks for it, and recording
        // itself does not depend on the level being sampled.
        if self.levelMeter.isActive {
          self.levelMeter.update(from: self.isRecordingPaused ? 0 : self.recorder.level())
          try? await Task.sleep(for: .milliseconds(45))
        } else {
          try? await Task.sleep(for: .milliseconds(300))
        }
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

  private func endLiveActivity() async {
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
