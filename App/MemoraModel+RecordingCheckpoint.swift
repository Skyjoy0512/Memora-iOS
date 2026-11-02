import Foundation

extension MemoraModel {
  /// Only acknowledge edits that reached SQLite. A failed checkpoint retains
  /// the previous draft and lets the recorder stop through its recovery path.
  @discardableResult
  func checkpointRecordingDraft() async -> Bool {
    guard !Task.isCancelled, (isRecording || isSavingCapture), !isRestoring, !isStoreProtected,
          var draft = recordingDraft, draft.id != nil,
          let url = recordingURL, MediaFiles.reference(for: url) == draft.fileName else { return false }
    guard draft.audioManifest.map({ $0.isValid(for: draft.id!, activeFileName: draft.fileName) }) ?? true else { return false }
    let previous = draft
    draft.title = recordingTitle
    draft.note = recordingNote
    draft.markers = recordingMarkers.isEmpty ? nil : recordingMarkers
    guard draft != recordingDraft else { return true }
    do {
      try await RecordStore.commitAsync(writes: [(key: StorageKey.recordingDraft, data: try RecordStore.encoded(draft))], removing: [])
    } catch { return false }
    guard !Task.isCancelled, !isRestoring, !isStoreProtected, (isRecording || isSavingCapture),
          recordingURL == url, recordingDraft?.id == previous.id,
          recordingDraft?.fileName == previous.fileName else { return false }
    // A newer acknowledged edit (for example a marker) wins over this write's
    // in-memory snapshot. The serial store queue preserves their disk ordering.
    if recordingDraft == previous { recordingDraft = draft }
    return true
  }
}
