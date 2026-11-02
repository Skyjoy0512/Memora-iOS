import AVFoundation
import Foundation

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
      checkpointStore: SourceMediaCheckpointStore(directory: directory), staging: staging) { await calls.recognize($0) }
    guard case .failed = failed else { preconditionFailure("Partial result was published") }
    let firstCount = await calls.count
    precondition(firstCount == 2)
    let complete = await RecordedAudioTranscription.transcribe(url, locale: Locale(identifier: "ja-JP"), vocabulary: [],
      checkpointStore: SourceMediaCheckpointStore(directory: directory), staging: staging) { await calls.recognize($0) }
    guard case .segments(let parts) = complete else { preconditionFailure("Could not resume") }
    let resumedCount = await calls.count
    precondition(resumedCount == 3 && parts.count == 2)
    precondition(parts[0].timestamp == 0.25 && parts[1].timestamp == 900.25)
    precondition(parts[1].endTime == 900.5 && parts[1].recognitionModel == "SpeechAnalyzer")
    let cached = await RecordedAudioTranscription.transcribe(url, locale: Locale(identifier: "ja-JP"), vocabulary: [],
      checkpointStore: SourceMediaCheckpointStore(directory: directory), staging: staging) { _ in
        preconditionFailure("Completed recording was recognized again")
      }
    guard case .segments(let restored) = cached else { preconditionFailure("Lost completed transcript") }
    precondition(restored == parts && FileManager.default.fileExists(atPath: url.path))
    let low = SourceMediaStaging(directory: root.appendingPathComponent("low-recording-stages"),
      availableCapacity: { _ in SourceMediaStaging.minimumAvailableBytes })
    let lowDisk = await RecordedAudioTranscription.transcribe(url, locale: Locale(identifier: "ja-JP"), vocabulary: [],
      checkpointStore: SourceMediaCheckpointStore(directory: directory), staging: low) { _ in
        preconditionFailure("Insufficient snapshot space reached recognition")
      }
    guard case .failed = lowDisk else { preconditionFailure("Insufficient disk accepted") }
    print("RecordedAudioTranscriptionChecks: PASS. Actual >50MB WAV snapshot and two AAC exports; failed suffix never published; SQLite resume across new store; timestamps/end times; completed reuse; low disk refusal. Recognizer fixture, no SpeechAnalyzer or iPhone RTF claim.")
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
