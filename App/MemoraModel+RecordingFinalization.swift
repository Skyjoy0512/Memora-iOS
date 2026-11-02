import Foundation

extension MemoraModel {
  func stopCapture() async {
    guard isRecording, !isSavingCapture else { return }
    isSavingCapture = true
    let startedAt = Date()
    let diagnostic = AudioProcessingDiagnostics.begin(.recordingFinalization)
    var diagnosticOutcome: AudioDiagnosticReport.Outcome = .cancelled
    defer {
      diagnostic?.finish(Task.isCancelled ? .cancelled : diagnosticOutcome)
      isSavingCapture = false
      performance.record(
        "保存（録音の確定）",
        milliseconds: Date.now.timeIntervalSince(startedAt) * 1_000
      )
    }

    let audioURL = recordingURL
    let workspaceGeneration = aiWorkspaceGeneration
    let originalDraftID = recordingDraft?.id, originalDraftName = recordingDraft?.fileName
    func ownsStoppedCapture() -> Bool {
      !Task.isCancelled && !isRestoring && !isStoreProtected && !isRecording &&
        recordingURL == audioURL && aiWorkspaceGeneration == workspaceGeneration &&
        recordingDraft?.id == originalDraftID && recordingDraft?.fileName == originalDraftName
    }
    stopRecorder()
    await endLiveActivity()
    guard ownsStoppedCapture() else { return }
    let checkpoint = diagnostic?.begin(.persistence)
    let checkpointed = await checkpointRecordingDraft()
    diagnostic?.end(checkpoint, outcome: checkpointed ? .success : .failed)
    guard ownsStoppedCapture() else { return }
    let draft = recordingDraft
    let recordID = draft?.id ?? UUID()
    func isCurrent() -> Bool {
      ownsStoppedCapture() && recordingDraft == draft
    }
    let verification = diagnostic?.begin(.verification)
    let measured = if let audioURL { await MediaFiles.duration(of: audioURL) } else { nil as TimeInterval? }
    guard isCurrent() else { return }
    guard !meetings.contains(where: { $0.id == recordID }),
          !lifeLogEntries.contains(where: { $0.id == recordID }) else { return }
    let duration = RecordingAudioValidation.duration(measured)
    diagnostic?.setAudioSeconds(duration)
    diagnostic?.end(verification, outcome: duration == nil ? .unavailable : .success)
    let hasFile = audioURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    let notice = hasFile ? RecordingAudioValidation.unreadableNotice : RecordingAudioValidation.missingNotice

    var meeting = Meeting(
      id: recordID,
      title: recordingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? "新しい会話"
        : recordingTitle.trimmingCharacters(in: .whitespacesAndNewlines),
      createdAt: recordingStartedAt ?? .now,
      duration: duration ?? 0,
      source: .recording,
      status: duration == nil ? .failed(notice) : .transcribing(0.12),
      summary: duration == nil ? notice : "録音を保存しました。文字起こしを準備しています。",
      keyPoints: [],
      decisions: [],
      openQuestions: [],
      transcript: [],
      spaceID: ProjectFiling.existingProject(recordingSpaceID, in: spaces),
      audioURL: audioURL
    )
    meeting.notes = recordingNote
    meeting.recordingMarkers = RecordingMarker.validated(recordingMarkers, duration: duration)
    meeting.calendarEventID = captureEvent?.id
    captureEvent = nil
    meetings.insert(meeting, at: 0)
    lifeLogEntries.insert(
      LifeLogEntry(
        id: meeting.id,
        createdAt: meeting.createdAt,
        title: meeting.title,
        summary: duration == nil ? "録音の保存情報を保持しました。音声ファイルを確認してください。" : "iPhoneで新しい音声を記録しました。",
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
    let persistence = diagnostic?.begin(.persistence)
    let committed = await commitRecordingSave()
    diagnostic?.end(persistence, outcome: committed ? .success : .failed)
    diagnosticOutcome = committed && duration != nil ? .success : .failed
    guard committed else {
      guard isCurrent() else { return }
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
    if recordingDraft == draft { recordingDraft = nil }
    guard !Task.isCancelled, !isRestoring, !isStoreProtected, recordingURL == audioURL,
          aiWorkspaceGeneration == workspaceGeneration else { return }
    noteRealSaveForSampleCleanup()
    finishCaptureSave(meetingID: meeting.id)
  }
}
