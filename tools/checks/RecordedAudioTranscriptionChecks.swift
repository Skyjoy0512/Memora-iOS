import AVFoundation
import CryptoKit
import Foundation
import Synchronization

enum RecordedAudioTranscriptionChecks {
  static func run(root: URL) async throws {
    let url = root.appendingPathComponent("long-recording.wav")
    let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    do {
      let file = try AVAudioFile(forWriting: url, settings: format.settings)
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096)!
      var remaining = 16_000 * 901
      while remaining > 0 {
        let count = min(remaining, 4_096)
        buffer.frameLength = AVAudioFrameCount(count)
        for index in 0..<count { buffer.floatChannelData![0][index] = 0 }
        try file.write(from: buffer)
        remaining -= count
      }
    }
    let directory = root.appendingPathComponent("recording-prefix")
    let staging = SourceMediaStaging(directory: root.appendingPathComponent("recording-stages"),
      availableCapacity: { _ in 10 * 1_024 * 1_024 * 1_024 })
    let calls = RecordingRecognitionFixture()
    let failed = await RecordedAudioTranscription.transcribe(url, locale: Locale(identifier: "ja-JP"), vocabulary: [],
      checkpointStore: SourceMediaCheckpointStore(directory: directory), staging: staging, checkReadiness: { try AudioProcessingReadiness.check(thermalState: .nominal) }) { await calls.recognize($0) }
    guard case .failed = failed else { preconditionFailure("Partial result was published") }
    let firstCount = await calls.count
    precondition(firstCount == 2)
    let checkpointKey = try recordingKey(url)
    let inspector = SourceMediaCheckpointStore(directory: directory)
    let firstCheckpoint = inspector.load(checkpointKey, duration: 901, session: inspector.begin())!
    let firstRevision = firstCheckpoint.chunkRevisions!.first!
    precondition(firstCheckpoint.chunkRevisions?.count == 1 && firstRevision.chunkIndex == 0)
    let complete = await RecordedAudioTranscription.transcribe(url, locale: Locale(identifier: "ja-JP"), vocabulary: [],
      checkpointStore: SourceMediaCheckpointStore(directory: directory), staging: staging, checkReadiness: { try AudioProcessingReadiness.check(thermalState: .nominal) }) { await calls.recognize($0) }
    guard case .segments(let parts) = complete else {
      if case .failed(let reason) = complete { preconditionFailure("Could not resume: \(reason)") }
      preconditionFailure("Could not resume: unexpected outcome \(complete)")
    }
    let resumedCount = await calls.count
    precondition(resumedCount == 3 && parts.count == 2)
    precondition(parts[0].timestamp == 0.25 && parts[1].timestamp == 900.25)
    precondition(parts[1].endTime == 900.5 && parts[1].recognitionModel == "SpeechAnalyzer")
    let finalCheckpoint = inspector.load(checkpointKey, duration: 901, session: inspector.begin())!
    precondition(finalCheckpoint.chunkRevisions?.map(\.chunkIndex) == [0, 1])
    precondition(finalCheckpoint.chunkRevisions?.first == firstRevision && finalCheckpoint.segments == parts)
    precondition(inspector.isCurrent(firstRevision, key: checkpointKey, duration: 901, session: inspector.begin()))
    let cached = await RecordedAudioTranscription.transcribe(url, locale: Locale(identifier: "ja-JP"), vocabulary: [],
      checkpointStore: SourceMediaCheckpointStore(directory: directory), staging: staging, checkReadiness: { try AudioProcessingReadiness.check(thermalState: .critical) }) { _ in
        preconditionFailure("Completed recording was recognized again")
      }
    guard case .segments(let restored) = cached else { preconditionFailure("Lost completed transcript") }
    precondition(restored == parts && FileManager.default.fileExists(atPath: url.path))
    let low = SourceMediaStaging(directory: root.appendingPathComponent("low-recording-stages"),
      availableCapacity: { _ in SourceMediaStaging.minimumAvailableBytes })
    let lowDisk = await RecordedAudioTranscription.transcribe(url, locale: Locale(identifier: "ja-JP"), vocabulary: [],
      checkpointStore: SourceMediaCheckpointStore(directory: directory), staging: low, checkReadiness: { try AudioProcessingReadiness.check(thermalState: .nominal) }) { _ in
        preconditionFailure("Insufficient snapshot space reached recognition")
      }
    guard case .failed = lowDisk else { preconditionFailure("Insufficient disk accepted") }
    let thermalDirectory = root.appendingPathComponent("thermal-prefix")
    let heat = Mutex<ProcessInfo.ThermalState>(.nominal)
    let thermalCalls = Mutex(0)
    let diagnostic = AudioDiagnosticSession(kind: .recordedTranscription) { _ in }
    let deferred = await AudioProcessingDiagnostics.$current.withValue(diagnostic) {
      await RecordedAudioTranscription.transcribe(url, locale: Locale(identifier: "ja-JP"), vocabulary: [],
        checkpointStore: SourceMediaCheckpointStore(directory: thermalDirectory), staging: staging,
        checkReadiness: { try AudioProcessingReadiness.check(thermalState: heat.withLock { $0 }) }) { _ in
        thermalCalls.withLock { $0 += 1 }
        heat.withLock { $0 = .serious }
        return .segments([.init(id: UUID(), speaker: "話者", speakerIsCertain: false,
          timestamp: 0.25, text: "確定した発話", endTime: 0.5)])
      }
    }
    guard case .failed = deferred else { preconditionFailure("Thermal prefix was published") }
    precondition(diagnostic.snapshot.outcome == .deferred && diagnostic.snapshot.completedChunks == 1)
    precondition(diagnostic.snapshot.maximumThermalState == 2)
    precondition(thermalCalls.withLock { $0 } == 1)
    heat.withLock { $0 = .nominal }
    let cooled = await RecordedAudioTranscription.transcribe(url, locale: Locale(identifier: "ja-JP"), vocabulary: [],
      checkpointStore: SourceMediaCheckpointStore(directory: thermalDirectory), staging: staging,
      checkReadiness: { try AudioProcessingReadiness.check(thermalState: heat.withLock { $0 }) }) { _ in
      thermalCalls.withLock { $0 += 1 }
      return .segments([.init(id: UUID(), speaker: "話者", speakerIsCertain: false,
        timestamp: 0.25, text: "確定した発話", endTime: 0.5)])
    }
    guard case .segments(let cooledParts) = cooled else { preconditionFailure("Thermal resume failed") }
    precondition(thermalCalls.withLock { $0 } == 2 && cooledParts.count == 2 && cooledParts[1].timestamp == 900.25)
    let readinessCalls = Mutex(0)
    let afterExport = await RecordedAudioTranscription.transcribe(url, locale: Locale(identifier: "ja-JP"), vocabulary: [],
      checkpointStore: SourceMediaCheckpointStore(directory: root.appendingPathComponent("post-export-thermal")), staging: staging,
      checkReadiness: {
        let call = readinessCalls.withLock { $0 += 1; return $0 }
        try AudioProcessingReadiness.check(thermalState: call == 1 ? .nominal : .critical)
      }) { _ in preconditionFailure("Heated export reached recognition") }
    guard case .failed = afterExport else { preconditionFailure("Post-export thermal pressure accepted") }
    precondition(readinessCalls.withLock { $0 } == 2 && FileManager.default.fileExists(atPath: url.path))
    try await RecordedAudioPreparationChecks.run(root: root, source: url)
    print("RecordedAudioTranscriptionChecks: PASS. Actual >50MB WAV snapshot and two AAC exports; failed suffix never published; SQLite resume across new store; timestamps/end times; completed reuse even at critical thermal state; low disk refusal; thermal prefix deferral and cooled suffix-only resume; post-export thermal gate. Recognizer fixture, no SpeechAnalyzer or iPhone RTF claim.")
  }

  private static func recordingKey(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var digest = SHA256()
    while let bytes = try handle.read(upToCount: 64 * 1_024), !bytes.isEmpty { digest.update(data: bytes) }
    let fingerprint = digest.finalize().map { String(format: "%02x", $0) }.joined()
    return try SourceMediaCheckpointStore.key(fingerprint: fingerprint, suffix: "wav",
      locale: Locale(identifier: "ja-JP"), vocabulary: [], pipeline: "recording-speech-analyzer-v1")
  }
}

private actor RecordingRecognitionFixture {
  var count = 0
  func recognize(_ url: URL) -> TranscriptionOutcome {
    precondition(FileManager.default.fileExists(atPath: url.path))
    count += 1
    if count == 2 { return .failed("fixture interrupted suffix") }
    return .segments([.init(id: UUID(), speaker: "話者", speakerIsCertain: false,
      timestamp: 0.25, text: "確定した発話", endTime: 0.5)])
  }
}
