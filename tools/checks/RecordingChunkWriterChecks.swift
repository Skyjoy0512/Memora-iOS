import AVFAudio
import Foundation
import Synchronization

@main
struct RecordingChunkWriterChecks {
  static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    var timeline = RecordingAudioManifest.starting(id: UUID(), fileName: "first.m4a")
    for index in 1..<96 {
      let rotation = RecordingRotation.make(previous: timeline, closedFrames: 44_100 * 900,
        nextFileName: "part-\(index).m4a")!
      precondition(rotation.isValid && rotation.next.parts[index].frameOffset == Int64(index) * 44_100 * 900)
      var forged = rotation
      forged.next.sampleRate = 48_000
      precondition(!forged.isValid)
      timeline = rotation.next
    }
    precondition(RecordingRotation.make(previous: timeline, closedFrames: 44_100 * 900,
      nextFileName: "beyond-day.m4a") == nil)
    precondition(RecordingRotation.make(previous: timeline, closedFrames: 0, nextFileName: "zero.m4a") == nil)
    precondition(RecordingRotation.make(previous: timeline, closedFrames: 1, nextFileName: "../outside.m4a") == nil)
    try await run(root: root, name: "fraction", frames: 110_250, expected: [44_100, 44_100, 22_050])
    try await run(root: root, name: "exact", frames: 88_200, expected: [44_100, 44_100])

    let folder = root.appendingPathComponent("refusal", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    let manifest = RecordingAudioManifest.starting(id: UUID(), fileName: "refusal.m4a")
    let refused = try RecordingChunkWriter(manifest: manifest, directory: folder, partFrames: 44_100) { _ in false }
    feed(refused, frames: 60_000)
    let refusal = await refused.finish()
    precondition(!refusal.isComplete)
    guard case .some(.persistence) = refusal.failure else { preconditionFailure("Unacknowledged transition accepted") }
    let refusedFiles = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    precondition(refusedFiles.count == 1)

    let collision = folder.appendingPathComponent("collision.m4a")
    let sentinel = Data("keep original".utf8)
    try sentinel.write(to: collision)
    let protected = try RecordingChunkWriter(manifest: .starting(id: UUID(), fileName: collision.lastPathComponent),
      directory: folder) { _ in preconditionFailure("Collision reached admission") }
    feed(protected, frames: 10)
    let collisionResult = await protected.finish()
    let retained = try Data(contentsOf: collision)
    precondition(!collisionResult.isComplete && retained == sentinel)
    print("PASS: rotation geometry/24h bounds, native AAC sliced frame counts, exact boundary/no empty tail, admission refusal and exclusive file creation. No microphone or SQLite model E2E.")
  }

  static func run(root: URL, name: String, frames: Int, expected: [Int64]) async throws {
    let folder = root.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    let transitions = Mutex<[RecordingRotation]>([])
    let writer = try RecordingChunkWriter(manifest: .starting(id: UUID(), fileName: "first.m4a"),
      directory: folder, partFrames: 44_100) { transition in
        precondition(transition.isValid)
        let old = transition.next.parts[transition.next.parts.count - 2]
        do {
          let closed = try AVAudioFile(forReading: folder.appendingPathComponent(old.fileName))
          precondition(closed.length == old.frameCount)
          precondition(!FileManager.default.fileExists(atPath: folder.appendingPathComponent(transition.next.parts.last!.fileName).path))
        } catch { preconditionFailure("Admission preceded a closed original") }
        transitions.withLock { $0.append(transition) }
        return true
      }
    feed(writer, frames: frames)
    let result = await writer.finish()
    precondition(result.isComplete && result.writtenFrames == Int64(frames))
    precondition(result.manifest.parts.map { $0.frameCount! } == expected)
    precondition(transitions.withLock { $0.count } == expected.count - 1)
    let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    precondition(files.count == expected.count)
    for part in result.manifest.parts {
      let file = try AVAudioFile(forReading: folder.appendingPathComponent(part.fileName))
      precondition(file.length == part.frameCount)
    }
  }

  static func feed(_ writer: RecordingChunkWriter, frames: Int) {
    let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    var position = 0
    // These fixtures stay below the 16-buffer bound; a live producer must stop
    // rather than retry when append refuses an input.
    while position < frames {
      let count = min(16_384, frames - position)
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
      buffer.frameLength = buffer.frameCapacity
      for index in 0..<count {
        buffer.floatChannelData![0][index] = Float(0.2 * sin(Double(position + index) * 2 * .pi * 440 / 44_100))
      }
      precondition(writer.append(buffer))
      position += count
    }
  }
}
