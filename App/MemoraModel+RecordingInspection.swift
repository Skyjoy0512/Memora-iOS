import Foundation

extension MemoraModel {
  func inspectRecordingDraft(_ draft: RecordingDraft?, legacyURL: URL?) async -> RecordingDraftInspection {
    guard let manifest = draft?.audioManifest else {
      let measured = if let legacyURL { await MediaFiles.duration(of: legacyURL) } else { nil as TimeInterval? }
      let hasFile = legacyURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
      return RecordingDraftInspection(playbackURL: legacyURL,
        duration: RecordingAudioValidation.duration(measured), manifest: nil,
        notice: hasFile ? RecordingAudioValidation.unreadableNotice : RecordingAudioValidation.missingNotice)
    }
    let generation = aiWorkspaceGeneration
    var frames: [Int64] = []
    for part in manifest.parts {
      guard !Task.isCancelled, !isRestoring, !isStoreProtected, recordingDraft == draft,
            aiWorkspaceGeneration == generation, let url = MediaFiles.resolve(part.fileName),
            let count = await MediaFiles.recordingFrameCount(of: url, sampleRate: manifest.sampleRate) else { break }
      frames.append(count)
    }
    let finalized = manifest.finalized(frameCounts: frames)
    // A lone part is the existing playable file. Multiple originals require an
    // assembled playback asset; never expose their last part as a full record.
    let playbackURL = manifest.parts.count == 1 ? MediaFiles.resolve(manifest.parts[0].fileName) : nil
    let hasFile = playbackURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    return RecordingDraftInspection(playbackURL: playbackURL, duration: finalized?.finalizedDuration,
      manifest: finalized ?? manifest,
      notice: manifest.parts.count > 1 ? RecordingAudioValidation.segmentedNotice
        : (hasFile ? RecordingAudioValidation.unreadableNotice : RecordingAudioValidation.missingNotice))
  }
}
