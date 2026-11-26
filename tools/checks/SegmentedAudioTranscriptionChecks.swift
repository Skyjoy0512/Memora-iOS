import AVFoundation
import Foundation
import Synchronization

enum SegmentedAudioTranscriptionChecks {
  static func run(root: URL) async throws {
    let originals = root.appendingPathComponent("part-originals", isDirectory: true)
    try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: false)
    let first = originals.appendingPathComponent("first.wav")
    let second = originals.appendingPathComponent("second.wav")
    try tone(first, rate: 8_000, frames: 450 * 8_000, frequency: 440)
    try tone(second, rate: 8_000, frames: 451 * 8_000, frequency: 880)
    let unchangedDate = Date(timeIntervalSince1970: 1_700_000_000)
    try FileManager.default.setAttributes([.modificationDate: unchangedDate], ofItemAtPath: second.path)
    let manifest = RecordingAudioManifest(recordingID: UUID(), sampleRate: 8_000, parts: [
      .init(fileName: "first.wav", frameOffset: 0, frameCount: 450 * 8_000, state: .finalized),
      .init(fileName: "second.wav", frameOffset: 450 * 8_000, frameCount: 451 * 8_000, state: .finalized)
    ])
    let input = RecordedAudioInput.parts(manifest, directory: originals)
    let stages = root.appendingPathComponent("part-stages")
    let staging = SourceMediaStaging(directory: stages, availableCapacity: { _ in 10 * 1_024 * 1_024 * 1_024 })
    let cache = root.appendingPathComponent("part-checkpoints")
    let calls = Mutex(0)
    let recognize: @Sendable (URL) async -> TranscriptionOutcome = { url in
      let count = calls.withLock { $0 += 1; return $0 }
      do {
        if count == 1 {
          try assertTone(url, time: 449.5, expected: 440, other: 880)
          try assertTone(url, time: 450.5, expected: 880, other: 440)
        } else { try assertTone(url, time: 0.25, expected: 880, other: 440) }
      } catch { preconditionFailure("Real export could not be read") }
      if count == 2 { return .failed("fixture suffix interrupted") }
      return segment()
    }
    let failed = await RecordedAudioTranscription.transcribe(input, locale: .init(identifier: "ja-JP"), vocabulary: [],
      checkpointStore: .init(directory: cache), staging: staging, checkReadiness: {}, recognize: recognize)
    guard case .failed = failed else { preconditionFailure("Published prefix of multiple originals") }
    let resumed = await RecordedAudioTranscription.transcribe(input, locale: .init(identifier: "ja-JP"), vocabulary: [],
      checkpointStore: .init(directory: cache), staging: staging, checkReadiness: {}, recognize: recognize)
    guard case .segments(let segments) = resumed else { preconditionFailure("Multipart resume failed") }
    precondition(calls.withLock { $0 } == 3 && segments.count == 2)
    precondition(segments[0].timestamp == 0.25 && segments[1].timestamp == 900.25 && segments[1].endTime == 900.5)
    let cached = await RecordedAudioTranscription.transcribe(input, locale: .init(identifier: "ja-JP"), vocabulary: [],
      checkpointStore: .init(directory: cache), staging: staging,
      checkReadiness: { throw SourceMediaFailure.thermalDeferred }) { _ in preconditionFailure("Completed multipart cache missed") }
    guard case .segments(let same) = cached else { preconditionFailure("Completed multipart cache lost") }
    precondition(same == segments)

    // Same file size and mtime cannot reuse the old content's result.
    let originalSize = try second.resourceValues(forKeys: [.fileSizeKey]).fileSize
    // Replace the samples through the encoder to keep the WAV container valid.
    try tone(second, rate: 8_000, frames: 451 * 8_000, frequency: 660)
    try FileManager.default.setAttributes([.modificationDate: unchangedDate], ofItemAtPath: second.path)
    let replacement = try URL(fileURLWithPath: second.path).resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
    precondition(replacement.fileSize == originalSize && replacement.contentModificationDate == unchangedDate)
    let changedCalls = Mutex(0)
    let changed = await RecordedAudioTranscription.transcribe(input, locale: .init(identifier: "ja-JP"), vocabulary: [],
      checkpointStore: .init(directory: cache), staging: staging, checkReadiness: {}) { _ in
        changedCalls.withLock { $0 += 1 }; return segment()
      }
    if case .failed(let reason) = changed { preconditionFailure("Changed original failed: \(reason)") }
    guard case .segments = changed else { preconditionFailure("Changed original produced no segments") }
    precondition(changedCalls.withLock { $0 } == 2)

    let mutated = Mutex(false)
    let during = await RecordedAudioTranscription.transcribe(input, locale: .init(identifier: "ja-JP"), vocabulary: ["別設定"],
      checkpointStore: .init(directory: cache), staging: staging, checkReadiness: {}) { _ in
        if mutated.withLock({ value in if value { return false }; value = true; return true }) {
          do {
            let file = try FileHandle(forUpdating: first)
            try file.seekToEnd(); try file.write(contentsOf: Data([0])); try file.close()
          } catch { preconditionFailure("Mutation fixture failed") }
        }
        return segment()
      }
    guard case .failed = during else { preconditionFailure("Changed original published transcript") }

    var unsealed = manifest
    unsealed.parts[1].state = .writing; unsealed.parts[1].frameCount = nil
    let refused = await RecordedAudioTranscription.transcribe(.parts(unsealed, directory: originals),
      locale: .init(identifier: "ja-JP"), vocabulary: [], checkpointStore: .init(directory: cache), staging: staging,
      checkReadiness: {}) { _ in preconditionFailure("Unsealed original reached recognition") }
    guard case .failed = refused else { preconditionFailure("Unsealed original accepted") }
    var wrongFrames = manifest; wrongFrames.parts[1].frameCount! -= 1
    let mismatch = await RecordedAudioTranscription.transcribe(.parts(wrongFrames, directory: originals),
      locale: .init(identifier: "ja-JP"), vocabulary: [], checkpointStore: .init(directory: cache), staging: staging,
      checkReadiness: {}) { _ in preconditionFailure("Mismatched frames reached recognition") }
    guard case .failed = mismatch else { preconditionFailure("Mismatched original accepted") }
    let link = originals.appendingPathComponent("link.wav")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: second)
    var linked = manifest; linked.parts[1].fileName = "link.wav"
    do { _ = try RecordedAudioInput.parts(linked, directory: originals).byteCount(); preconditionFailure("Symlink accepted") }
    catch SourceMediaFailure.invalidTemporaryFile { }
    let large = originals.appendingPathComponent("large.wav")
    FileManager.default.createFile(atPath: large.path, contents: nil)
    let sparse = try FileHandle(forWritingTo: large)
    try sparse.truncate(atOffset: UInt64(SourceMediaStaging.maximumInputBytes)); try sparse.close()
    var oversized = manifest; oversized.parts[1].fileName = "large.wav"
    do { _ = try RecordedAudioInput.parts(oversized, directory: originals).byteCount(); preconditionFailure("Aggregate budget ignored") }
    catch SourceMediaFailure.stagingLimit { }
    try FileManager.default.removeItem(at: large)
    let stageFiles = try FileManager.default.contentsOfDirectory(at: stages, includingPropertiesForKeys: nil)
    precondition(stageFiles.isEmpty && FileManager.default.fileExists(atPath: first.path) && FileManager.default.fileExists(atPath: second.path))
    try await aacParts(root: root, staging: staging)
    print("PASS: actual multipart WAV/AAC composition, cross-original tones, 15m suffix SQLite resume, global timestamps, complete cache, hash change despite same size/mtime, mutation refusal, unsealed/frames/link/aggregate limits, staging cleanup. Recognition is a fixture.")
  }

  static func segment() -> TranscriptionOutcome {
    .segments([.init(id: UUID(), speaker: "話者", speakerIsCertain: false, timestamp: 0.25, text: "確定区間", endTime: 0.5)])
  }

  static func tone(_ url: URL, rate: Double, frames: Int, frequency: Double) throws {
    let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
    let output = try AVAudioFile(forWriting: url, settings: format.settings)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096)!
    var written = 0
    while written < frames {
      let count = min(4_096, frames - written)
      buffer.frameLength = AVAudioFrameCount(count)
      for index in 0..<count {
        buffer.floatChannelData![0][index] = Float(0.25 * sin(2 * .pi * frequency * Double(written + index) / rate))
      }
      try output.write(from: buffer); written += count
    }
  }

  static func assertTone(_ url: URL, time: Double, expected: Double, other: Double) throws {
    let file = try AVAudioFile(forReading: url)
    file.framePosition = Int64(time * file.processingFormat.sampleRate)
    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1_024)!
    try file.read(into: buffer)
    precondition(buffer.frameLength == 1_024)
    func power(_ frequency: Double) -> Double {
      var real = 0.0, imaginary = 0.0
      for index in 0..<Int(buffer.frameLength) {
        let value = Double(buffer.floatChannelData![0][index])
        let phase = 2 * .pi * frequency * Double(index) / file.processingFormat.sampleRate
        real += value * cos(phase); imaginary += value * sin(phase)
      }
      return real * real + imaginary * imaginary
    }
    precondition(power(expected) > power(other) * 10, "Original order/time was not preserved in export")
  }

  static func aacParts(root: URL, staging: SourceMediaStaging) async throws {
    let folder = root.appendingPathComponent("aac-originals", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    var parts: [RecordingAudioPart] = []
    var offset: Int64 = 0
    for index in 0..<2 {
      let wav = folder.appendingPathComponent("\(index).wav"), m4a = folder.appendingPathComponent("\(index).m4a")
      try tone(wav, rate: 44_100, frames: 44_100, frequency: index == 0 ? 440 : 880)
      let export = AVAssetExportSession(asset: AVURLAsset(url: wav), presetName: AVAssetExportPresetAppleM4A)!
      try await export.export(to: m4a, as: .m4a)
      let file = try AVAudioFile(forReading: m4a)
      parts.append(.init(fileName: m4a.lastPathComponent, frameOffset: offset, frameCount: file.length, state: .finalized))
      offset += file.length
    }
    let manifest = RecordingAudioManifest(recordingID: UUID(), sampleRate: 44_100, parts: parts)
    let result = await RecordedAudioTranscription.transcribe(.parts(manifest, directory: folder), locale: .init(identifier: "ja-JP"),
      vocabulary: [], checkpointStore: .init(directory: root.appendingPathComponent("aac-cache")), staging: staging,
      checkReadiness: {}) { url in
        do { try assertTone(url, time: 0.5, expected: 440, other: 880); try assertTone(url, time: 1.5, expected: 880, other: 440) }
        catch { preconditionFailure("AAC export unreadable") }
        return segment()
      }
    guard case .segments = result else { preconditionFailure("Native AAC originals could not be composed") }
  }
}
