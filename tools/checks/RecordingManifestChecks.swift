import AVFoundation
import Foundation

@MainActor
enum RecordingManifestChecks {
  nonisolated static func expect(_ value: Bool, _ message: String = "Manifest check failed") { precondition(value, message) }

  static func run(_ root: URL) async throws {
    let id = UUID()
    let one = RecordingAudioManifest.starting(id: id, fileName: "one.m4a")
    expect(one.isValid(for: id, activeFileName: "one.m4a"))
    expect(one.finalizedDuration == nil && one.finalized(frameCounts: [11_025])?.finalizedDuration == 0.25)
    expect(one.finalized(frameCounts: [11_025])!.preservesTimeline(of: one))
    expect(!one.isValid(for: UUID()) && !one.isValid(for: id, activeFileName: "wrong.m4a"))
    var invalid = one
    for version in [0, 2, Int.max] { invalid = one; invalid.version = version; expect(!invalid.isValid(for: id)) }
    for rate in [0, -1, Int.max, 192_001] { invalid = one; invalid.sampleRate = rate; expect(!invalid.isValid(for: id)) }
    for name in ["", ".", "..", "../one.m4a", "/tmp/one.m4a", "a\\b", "a\0b", String(repeating: "a", count: 256)] {
      invalid = one; invalid.parts[0].fileName = name; expect(!invalid.isValid(for: id))
    }
    invalid = one; invalid.parts[0].frameOffset = 1; expect(!invalid.isValid(for: id))
    invalid = one; invalid.parts[0].frameCount = 0; expect(!invalid.isValid(for: id))
    invalid = one; invalid.parts.append(one.parts[0]); expect(!invalid.isValid(for: id))
    invalid = one; invalid.parts = []; expect(!invalid.isValid(for: id))
    invalid = one; invalid.parts = Array(repeating: one.parts[0], count: 129); expect(!invalid.isValid(for: id))
    for frames in [Int64(0), -1, .max, 44_100 * 86_400 + 1] {
      expect(one.finalized(frameCounts: [frames]) == nil)
    }
    expect(one.finalized(frameCounts: []) == nil)
    let day = RecordingAudioManifest(recordingID: id, sampleRate: 44_100, parts: (0..<96).map { index in
      .init(fileName: "\(index).m4a", frameOffset: Int64(index) * 900 * 44_100,
        frameCount: 900 * 44_100, state: .finalized)
    })
    expect(day.isValid(for: id) && day.finalizedDuration == 86_400)
    expect(day.finalized(frameCounts: Array(repeating: 900 * 44_100, count: 96)) == day)
    invalid = day; invalid.parts[12].frameOffset += 1; expect(!invalid.isValid(for: id))
    invalid = day; invalid.parts[12].frameOffset -= 1; expect(!invalid.isValid(for: id))
    invalid = day; invalid.parts[12].state = .writing; invalid.parts[12].frameCount = nil
    expect(!invalid.isValid(for: id))

    for scenario in 0..<4 { try await recoverParts(root, scenario: scenario) }
    try await finishSingle(root)
    for change in 0..<6 { try await staleInspection(root, change: change) }
    try await refuseInvalid(root)
    try await nativeFrames(root)
    print("PASS: recording manifest frame continuity/24h/bounds, all-original recovery and SQLite reopen, partial inference refusal, single-part finalization, 6 stale inspections, invalid manifest retention, real PCM frame metadata")
  }

  static func partsFixture(_ root: URL) throws -> (MemoraModel, URL, MemoraModel.RecordingDraft) {
    let (model, current, original) = try RecordingFinalizationChecks.fixture(root, "manifest-" + UUID().uuidString)
    let earlier = MediaFiles.directory.appendingPathComponent(UUID().uuidString + ".m4a")
    try Data("Earlier original retained".utf8).write(to: earlier)
    var draft = original
    draft.audioManifest = .init(recordingID: draft.id!, sampleRate: 44_100, parts: [
      .init(fileName: earlier.lastPathComponent, frameOffset: 0, frameCount: 44_100, state: .finalized),
      .init(fileName: current.lastPathComponent, frameOffset: 44_100, frameCount: nil, state: .writing)
    ])
    model.recordingDraft = draft
    model.persistRecordingDraft()
    return (model, current, draft)
  }

  static func recoverParts(_ root: URL, scenario: Int) async throws {
    let (model, current, draft) = try partsFixture(root)
    model.isRecording = false
    let earlierName = draft.audioManifest!.fileNames[0]
    let original = try Data(contentsOf: MediaFiles.resolve(earlierName)!)
    if scenario == 1 { try FileManager.default.removeItem(at: current) }
    MediaFiles.readFrames = { url, rate in
      expect(rate == 44_100)
      if scenario == 1 && url == current { return nil }
      if scenario == 2 { return nil }
      if scenario == 3 && url.lastPathComponent == earlierName { return 44_101 }
      return 44_100
    }
    await model.recoverRecordingDraft()
    expect(model.recordingDraft == nil && model.meetings.count == 1 && model.lifeLogEntries.count == 1)
    let record = model.meetings[0]
    expect(record.audioURL == nil && record.originalAudioFileNames == draft.audioManifest!.fileNames)
    expect(record.notes == draft.note && record.transcript.isEmpty && model.processed.isEmpty)
    guard case .failed = record.status else { preconditionFailure("Unassembled originals claimed readiness") }
    expect(record.duration == (scenario == 0 ? 2 : 0))
    expect(record.recordingAudioManifest?.parts.last?.state == (scenario == 0 ? .finalized : .writing))
    if scenario != 0 { expect(record.recordingMarkers == draft.markers) }
    let reopened = LocalStore(fileURL: model.storeURL); try reopened.prepare()
    let saved = try RecordingRecoveryChecksShim.records(reopened)
    expect(saved[0].recordingAudioManifest == record.recordingAudioManifest)
    expect(saved[0].originalAudioFileNames == record.originalAudioFileNames)
    expect(try Data(contentsOf: MediaFiles.resolve(earlierName)!) == original)
    await model.recoverRecordingDraft()
    expect(model.meetings.count == 1)
  }

  static func finishSingle(_ root: URL) async throws {
    let (model, url, original) = try RecordingFinalizationChecks.fixture(root, "single-manifest")
    var draft = original
    draft.audioManifest = .starting(id: draft.id!, fileName: draft.fileName)
    model.recordingDraft = draft
    model.persistRecordingDraft()
    MediaFiles.readFrames = { _, _ in 11_025 }
    await model.stopCapture()
    expect(model.recordingDraft == nil && model.meetings.count == 1)
    let saved = model.meetings[0]
    expect(saved.duration == 0.25 && saved.audioURL == url && saved.originalAudioFileNames == [url.lastPathComponent])
    expect(saved.recordingAudioManifest?.finalizedDuration == 0.25 && model.processed == [saved.id])
    expect(saved.calendarEventID == "retained-calendar-id")
  }

  static func staleInspection(_ root: URL, change: Int) async throws {
    let (model, _, draft) = try partsFixture(root)
    model.isRecording = false
    let gate = RecordingRecoveryGate<Int64?>()
    MediaFiles.readFrames = { _, _ in await gate.wait() }
    let operation = Task { await model.recoverRecordingDraft() }
    await gate.entered()
    switch change {
    case 0: model.aiWorkspaceGeneration = UUID()
    case 1: model.recordingDraft?.audioManifest?.parts[0].frameCount = 1
    case 2: model.isStoreProtected = true
    case 3: model.isRestoring = true
    case 4: operation.cancel()
    default: model.recordingDraft?.id = UUID()
    }
    let expected = model.recordingDraft
    gate.resume(44_100)
    await operation.value
    expect(model.meetings.isEmpty && model.lifeLogEntries.isEmpty && model.recordingDraft == expected)
    expect(draft.audioManifest!.fileNames.allSatisfy { FileManager.default.fileExists(atPath: MediaFiles.resolve($0)!.path) })
  }

  static func refuseInvalid(_ root: URL) async throws {
    let (model, _, original) = try partsFixture(root)
    model.isRecording = false
    model.recordingDraft?.audioManifest?.parts[1].frameOffset = .max
    let draft = model.recordingDraft
    MediaFiles.readFrames = { _, _ in preconditionFailure("Invalid manifest inspected audio") }
    await model.recoverRecordingDraft()
    expect(model.recordingDraft == draft && model.meetings.isEmpty && model.recordingErrorMessage != nil)
    model.recordingDraft = original
    model.lifeLogEntries = [.init(id: original.id!, createdAt: .now, title: "Other", summary: "Keep", source: .iphone)]
    await model.recoverRecordingDraft()
    expect(model.recordingDraft == original && model.lifeLogEntries.count == 1)
    model.lifeLogEntries = []
    var other = Meeting(id: original.id!, title: "Existing", createdAt: .now, duration: 0,
      source: .recording, status: .failed("Keep"), summary: "Keep", keyPoints: [], decisions: [], openQuestions: [],
      transcript: [], spaceID: nil, audioURL: nil)
    other.originalAudioFileNames = original.audioManifest!.fileNames
    other.recordingAudioManifest = original.audioManifest
    other.recordingAudioManifest?.sampleRate = 48_000
    model.meetings = [other]
    await model.recoverRecordingDraft()
    expect(model.recordingDraft == original && model.meetings == [other])
    model.hasUnsavedRecording = true
    model.meetings[0].recordingAudioManifest = original.audioManifest
    await model.recoverRecordingDraft()
    expect(model.recordingDraft == original, "Unsaved in-memory record cleared recovery draft")
    model.hasUnsavedRecording = false
    model.meetings = []
    model.isRecording = true
    model.recordingDraft?.audioManifest?.parts[1].frameOffset = -1
    expect(await !model.checkpointRecordingDraft())
  }

  static func nativeFrames(_ root: URL) async throws {
    let fileURL = root.appendingPathComponent("native-frames.wav")
    let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    do {
      let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410)!
      buffer.frameLength = 4_410
      memset(buffer.floatChannelData![0], 0, 4_410 * MemoryLayout<Float>.size)
      try file.write(from: buffer)
    }
    expect(await RecordingAudioValidation.frameCount(of: fileURL, sampleRate: 44_100) == 4_410)
    let m4a = root.appendingPathComponent("native-frames.m4a")
    let exporter = AVAssetExportSession(asset: AVURLAsset(url: fileURL), presetName: AVAssetExportPresetAppleM4A)!
    try await exporter.export(to: m4a, as: .m4a)
    let aacFrames = await RecordingAudioValidation.frameCount(of: m4a, sampleRate: 44_100)
    expect(aacFrames != nil && aacFrames! > 0 && aacFrames! <= 8_192)
    expect(await RecordingAudioValidation.frameCount(of: fileURL, sampleRate: 48_000) == nil)
    expect(await RecordingAudioValidation.frameCount(of: root, sampleRate: 44_100) == nil)
    let link = root.appendingPathComponent("native-link.wav")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fileURL)
    expect(await RecordingAudioValidation.frameCount(of: link, sampleRate: 44_100) == nil)
    let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return await RecordingAudioValidation.frameCount(of: fileURL, sampleRate: 44_100) }
    expect(await task.value == nil)
  }
}

@MainActor
private enum RecordingRecoveryChecksShim {
  static func records(_ store: LocalStore) throws -> [Meeting] {
    guard case .data(let data) = store.readOutcome(MemoraModel.StorageKey.meetings) else { preconditionFailure("Missing records") }
    return try JSONDecoder().decode([Meeting].self, from: data)
  }
}
