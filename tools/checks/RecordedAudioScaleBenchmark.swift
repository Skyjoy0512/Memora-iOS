import AVFoundation
import Darwin
import Foundation
import Synchronization

/// Exercises the real local recording input, staging, export and checkpoint path.
/// Synthetic AAC and a deterministic recognizer keep this independent of devices and services.
enum RecordedAudioScaleBenchmark {
  enum Failure: Error { case unsupportedDuration, invalidFixture, invalidPipelineResult }

  private struct Measurement: Encodable {
    var hours: Int
    var audioSeconds: TimeInterval
    var sampleRate: Int
    var chunks: Int
    var inputBytes: Int64
    var exportedBytes: Int64
    var peakObservedStageBytes: Int64
    var wallSeconds: Double
    var snapshotSeconds: Double
    var exportSeconds: Double
    var verificationSeconds: Double
    var processCPUSeconds: Double?
    var processPeakRSSBytes: Int?
    var sampledPeakFootprintBytes: UInt64?
    var environment: AudioDiagnosticEnvironment
    var boundary = "macOS host; synthetic mono AAC, fixture recognition, no network or speech quality measurement"
  }

  private struct Exports: Sendable {
    var bytes: Int64 = 0
    var peakStageBytes: Int64 = 0
  }

  static func run(hours: Int, root: URL) async throws {
    let run = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let originals = run.appendingPathComponent("originals", isDirectory: true)
    try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: run) }
    let sampleRate = 16_000
    let secondsPerPart = Int(SourceMediaChunk.durationPerChunk)
    let parts = try makeParts(seconds: hours * 3_600, secondsPerPart: secondsPerPart,
      sampleRate: sampleRate, in: originals)
    let manifest = RecordingAudioManifest(recordingID: UUID(), sampleRate: sampleRate, parts: parts)
    guard let duration = manifest.finalizedDuration, duration == Double(hours * 3_600) else { throw Failure.invalidFixture }
    let input = RecordedAudioInput.parts(manifest, directory: originals)
    let inputBytes = try input.byteCount()
    let stages = run.appendingPathComponent("stages", isDirectory: true)
    let staging = SourceMediaStaging(directory: stages)
    let checkpoints = SourceMediaCheckpointStore(directory: run.appendingPathComponent("checkpoints"))
    let metrics = AudioDiagnosticSession(kind: .recordedTranscription, audioSeconds: duration) { _ in }
    let exports = Mutex(Exports())
    let started = resourceUsage()
    metrics.startSampling(interval: .seconds(1)) { true }
    let outcome = await AudioProcessingDiagnostics.$current.withValue(metrics) {
      await RecordedAudioTranscription.transcribe(input, locale: .init(identifier: "ja-JP"), vocabulary: [],
        checkpointStore: checkpoints, staging: staging) { url in
        do {
          let audio = try AVAudioFile(forReading: url)
          let seconds = Double(audio.length) / audio.processingFormat.sampleRate
          guard abs(seconds - Double(secondsPerPart)) < 0.25,
                let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, bytes > 0 else {
            return .failed("Fixture output had an unexpected audio duration")
          }
          let stageBytes = try SourceMediaStaging.size(of: url.deletingLastPathComponent())
          exports.withLock {
            $0.bytes += Int64(bytes)
            $0.peakStageBytes = max($0.peakStageBytes, stageBytes)
          }
          return .segments([.init(id: UUID(), speaker: "fixture", speakerIsCertain: false,
            timestamp: 0.25, text: "fixture", endTime: 0.5)])
        } catch { return .failed("Fixture could not read exported audio") }
      }
    }
    let finished = resourceUsage()
    metrics.sample(await AudioResourceProbe.capture())
    metrics.finish(outcome.diagnosticOutcome)
    let report = metrics.snapshot
    let result = exports.withLock { $0 }
    guard case .segments(let segments) = outcome, segments.count == parts.count,
          segments.enumerated().allSatisfy({ index, segment in
            segment.timestamp == Double(index * secondsPerPart) + 0.25 &&
              segment.endTime == Double(index * secondsPerPart) + 0.5
          }), report.completedChunks == parts.count, report.reusedChunks == 0,
          try FileManager.default.contentsOfDirectory(atPath: stages.path).isEmpty else {
      throw Failure.invalidPipelineResult
    }
    let cpuSeconds = started.flatMap { first in finished.map { $0.cpuSeconds - first.cpuSeconds } }
    let measurement = Measurement(hours: hours, audioSeconds: duration, sampleRate: sampleRate,
      chunks: parts.count, inputBytes: inputBytes, exportedBytes: result.bytes, peakObservedStageBytes: result.peakStageBytes,
      wallSeconds: report.wallSeconds, snapshotSeconds: report.totals["snapshot"]?.wallSeconds ?? 0,
      exportSeconds: report.totals["exportAudio"]?.wallSeconds ?? 0,
      verificationSeconds: report.totals["verification"]?.wallSeconds ?? 0, processCPUSeconds: cpuSeconds,
      processPeakRSSBytes: finished?.peakRSS, sampledPeakFootprintBytes: report.sampledPeakFootprintBytes,
      environment: report.environment)
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    print(String(decoding: try encoder.encode(measurement), as: UTF8.self))
  }

  private static func makeParts(seconds: Int, secondsPerPart: Int, sampleRate: Int,
                                in directory: URL) throws -> [RecordingAudioPart] {
    let source = directory.appendingPathComponent("part-0.m4a")
    try writeTone(seconds: secondsPerPart, sampleRate: sampleRate, to: source)
    guard try AVAudioFile(forReading: source).length == Int64(secondsPerPart * sampleRate) else { throw Failure.invalidFixture }
    return try (0..<(seconds / secondsPerPart)).map { index in
      let name = "part-\(index).m4a"
      if index > 0 { try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(name)) }
      return RecordingAudioPart(fileName: name, frameOffset: Int64(index * secondsPerPart * sampleRate),
        frameCount: Int64(secondsPerPart * sampleRate), state: .finalized)
    }
  }

  private static func writeTone(seconds: Int, sampleRate: Int, to url: URL) throws {
    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate,
      AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32_000]
    let writer = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: writer.processingFormat, frameCapacity: AVAudioFrameCount(sampleRate)),
          let samples = buffer.floatChannelData?[0] else { throw Failure.invalidFixture }
    buffer.frameLength = buffer.frameCapacity
    for index in 0..<(sampleRate / 2) {
      samples[index] = Float(sin(2 * .pi * 440 * Double(index) / Double(sampleRate)) * 0.25)
    }
    for index in (sampleRate / 2)..<sampleRate { samples[index] = 0 }
    for _ in 0..<seconds { try writer.write(from: buffer) }
  }

  private static func resourceUsage() -> (cpuSeconds: Double, peakRSS: Int)? {
    var value = rusage()
    guard getrusage(RUSAGE_SELF, &value) == 0 else { return nil }
    func seconds(_ time: timeval) -> Double { Double(time.tv_sec) + Double(time.tv_usec) / 1e6 }
    return (seconds(value.ru_utime) + seconds(value.ru_stime), value.ru_maxrss)
  }
}
