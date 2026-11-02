import AVFoundation
import Foundation

@main struct SourceMediaExportChecks {
  static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let staging = SourceMediaStaging(directory: root.appendingPathComponent("stages"), availableCapacity: { _ in 10 * 1_024 * 1_024 * 1_024 })
    let stage = try await staging.acquire()
    defer { stage.remove() }
    let original = root.appendingPathComponent("fixture.wav")
    try makeAudio(original)
    let export = SourceMediaAudioExport(asset: AVURLAsset(url: original), temporaryDirectory: stage.directory)!
    try await export.write(to: stage.audioURL, stageDirectory: stage.directory)
    let duration = try await AVURLAsset(url: stage.audioURL).load(.duration).seconds
    precondition(duration > 0.9 && duration < 1.2)
    try SourceMediaAudioExport.validateOutput(stage.audioURL, stageDirectory: stage.directory)

    let chunks = try SourceMediaChunk.plan(duration: 1_800.5)
    precondition(chunks.map(\.start) == [0, 900, 1_800])
    precondition(chunks.map(\.duration) == [900, 900, 0.5])
    let longest = try SourceMediaChunk.plan(duration: SourceMediaChunk.maximumDuration)
    precondition(longest.count == 24)
    for invalid in [Double.nan, Double.infinity, 0, -1, SourceMediaChunk.maximumDuration + 1] {
      do { _ = try SourceMediaChunk.plan(duration: invalid); preconditionFailure("Invalid duration") }
      catch SourceMediaFailure.invalidDuration { }
    }
    let partStage = try await staging.acquire()
    let part = SourceMediaAudioExport(asset: AVURLAsset(url: original), temporaryDirectory: partStage.directory,
      chunk: SourceMediaChunk(start: 0.25, duration: 0.5))!
    try await part.write(to: partStage.audioURL, stageDirectory: partStage.directory)
    let partDuration = try await AVURLAsset(url: partStage.audioURL).load(.duration).seconds
    precondition(partDuration > 0.45 && partDuration < 0.65)
    partStage.remove()
    precondition(!FileManager.default.fileExists(atPath: partStage.directory.path))

    let orphan = stage.directory.deletingLastPathComponent().appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: false)
    try Data().write(to: orphan.appendingPathComponent(".lease"))
    try Data("uncompleted audio".utf8).write(to: orphan.appendingPathComponent("audio.m4a"))
    try await staging.cleanupStale(now: .now.addingTimeInterval(2 * 60 * 60))
    precondition(!FileManager.default.fileExists(atPath: orphan.path))
    precondition(FileManager.default.fileExists(atPath: stage.audioURL.path))
    let starting = stage.directory.deletingLastPathComponent().appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: starting, withIntermediateDirectories: false)
    try await staging.cleanupStale()
    precondition(FileManager.default.fileExists(atPath: starting.path))
    try await staging.cleanupStale(now: .now.addingTimeInterval(2 * 60 * 60))
    precondition(!FileManager.default.fileExists(atPath: starting.path))

    let bounded = try await staging.acquire()
    defer { bounded.remove() }
    FileManager.default.createFile(atPath: bounded.audioURL.path, contents: nil)
    let handle = try FileHandle(forWritingTo: bounded.audioURL)
    try handle.truncate(atOffset: UInt64(SourceMediaAudioExport.maximumOutputBytes + 1))
    try handle.close()
    do {
      try SourceMediaAudioExport.validateOutput(bounded.audioURL, stageDirectory: bounded.directory)
      preconditionFailure("Oversized audio must never reach recognition")
    } catch SourceMediaFailure.exportTooLarge { }
    bounded.remove()

    let low = SourceMediaStaging(directory: root.appendingPathComponent("low-space"), availableCapacity: { _ in 1 })
    do { _ = try await low.acquire(); preconditionFailure("Low disk must be refused") }
    catch SourceMediaFailure.capacity { }
    let cancelledStage = try await staging.acquire()
    let cancelledExport = SourceMediaAudioExport(asset: AVURLAsset(url: original), temporaryDirectory: cancelledStage.directory)!
    let cancelled = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      try await cancelledExport.write(to: cancelledStage.audioURL, stageDirectory: cancelledStage.directory)
    }
    do { try await cancelled.value; preconditionFailure("Cancelled export must stop") }
    catch is CancellationError { }
    cancelledStage.remove()
    precondition(!FileManager.default.fileExists(atPath: cancelledStage.directory.path))
    stage.remove()
    precondition(!FileManager.default.fileExists(atPath: stage.directory.path))
    print("SourceMediaExportChecks: PASS. Actual local AVFoundation WAV-to-M4A export, selected time range, bounded chunk plans, retained duration, strict sparse-file capacity rejection, low-disk preflight, pre-cancel refusal, active flock preservation, unlocked orphan and incomplete-stage cleanup. Host macOS; no speech/device/in-flight cancellation timing claim.")
  }

  private static func makeAudio(_ url: URL) throws {
    let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
    buffer.frameLength = 16_000
    for index in 0..<16_000 { buffer.floatChannelData![0][index] = Float(sin(Double(index) * 0.04) * 0.05) }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
  }
}
