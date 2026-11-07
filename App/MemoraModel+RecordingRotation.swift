import Foundation

extension MemoraModel {
  /// Called by a continuous writer before it opens the next original. Use the
  /// serial synchronous commit so older queued checkpoints cannot land later.
  func admitRecordingRotation(_ rotation: RecordingRotation, generation: UUID) -> Bool {
    guard !Task.isCancelled, rotation.isValid, !isRestoring, !isStoreProtected, currentTeamID == nil,
          aiWorkspaceGeneration == generation, isRecording || isSavingCapture,
          var draft = recordingDraft, draft.id == rotation.previous.recordingID,
          draft.audioManifest == rotation.previous,
          draft.fileName == rotation.previous.parts.last?.fileName,
          let currentURL = recordingURL, MediaFiles.reference(for: currentURL) == draft.fileName,
          let nextName = rotation.next.parts.last?.fileName else { return false }
    // The next original does not exist yet; the writer creates it after this
    // admission. Validate the name without requiring the file to be present.
    let nextURL = MediaFiles.directory.appendingPathComponent(nextName)
    guard MediaFiles.reference(for: nextURL) == nextName else { return false }
    guard !FileManager.default.fileExists(atPath: nextURL.path) else { return false }
    draft.fileName = nextName
    draft.audioManifest = rotation.next
    draft.title = recordingTitle
    draft.note = recordingNote
    draft.markers = recordingMarkers.isEmpty ? nil : recordingMarkers
    guard persistNow(draft, forKey: StorageKey.recordingDraft) else { return false }
    recordingDraft = draft
    recordingURL = nextURL
    return true
  }
}
