import AVFAudio
import Foundation

@MainActor
final class PlaybackQueueFixture {
  var source: AudioPlaybackSource?
  var scheduledFiles: [Int64: AVAudioFile] = [:]
  var isPlaying = false
  var playbackSchedule = AudioPlaybackSchedule()
  var player = PlaybackNodeFixture()
  var failures = 0
  func failPlayback() {
    failures += 1
    isPlaying = false
    playbackSchedule.cancel()
    scheduledFiles.removeAll()
  }
}

@MainActor
final class PlaybackNodeFixture {
  struct Reservation {
    var start: Int64
    var count: UInt32
    var file: AVAudioFile
    var completion: @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void
  }
  var reservations: [Reservation] = []
  func scheduleSegment(_ file: AVAudioFile, startingFrame: Int64, frameCount: UInt32,
                       at: AVAudioTime?, completionCallbackType: AVAudioPlayerNodeCompletionCallbackType,
                       completionHandler: @escaping @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void) {
    precondition(completionCallbackType == .dataPlayedBack)
    reservations.append(.init(start: startingFrame, count: frameCount, file: file, completion: completionHandler))
  }
}

@main
struct AudioPlaybackChecks {
  @MainActor
  static func main() async throws {
    for rate in [8_000.0, 44_100, 48_000, 96_000, 192_000] {
      let length = Int64(rate * 86_400)
      var plan = AudioPlaybackSchedule()
      var pending = plan.start(at: 0, length: length, sampleRate: rate)
      var expected: Int64 = 0
      var count = 0
      while !pending.isEmpty {
        precondition(pending.count <= 2)
        let segment = pending.removeFirst()
        precondition(segment.start == expected && segment.count > 0)
        expected += Int64(segment.count)
        count += 1
        if let next = plan.complete(segment) { pending.append(next) }
        precondition(plan.complete(segment) == nil, "Duplicate completion advanced the cursor")
      }
      precondition(expected == length && count == 1_440)
    }

    var plan = AudioPlaybackSchedule()
    let original = plan.start(at: 10, length: 10_000, sampleRate: 1)
    let replacement = plan.start(at: 1_000, length: 10_000, sampleRate: 1)
    for old in original { precondition(plan.complete(old) == nil) }
    precondition(plan.complete(replacement[1])?.start == 1_120)
    plan.cancel()
    precondition(plan.complete(replacement[0]) == nil)
    precondition(plan.start(at: -1, length: 100, sampleRate: 1).isEmpty)
    precondition(plan.start(at: 100, length: 100, sampleRate: 1).isEmpty)
    for invalid in [Double.nan, .infinity, -.infinity, 0, -1] {
      precondition(plan.start(at: 0, length: 100, sampleRate: invalid).isEmpty)
    }
    let huge = plan.start(at: Int64.max - 100, length: .max, sampleRate: .greatestFiniteMagnitude)
    precondition(huge.count == 1 && huge[0].count == 100 && plan.complete(huge[0]) == nil)
    let bounded = plan.start(at: 0, length: .max, sampleRate: .greatestFiniteMagnitude)
    precondition(bounded.count == 2 && bounded.allSatisfy { $0.count == UInt32.max })
    let tiny = plan.start(at: 0, length: 2, sampleRate: 0.001)
    precondition(tiny.count == 2 && tiny.allSatisfy { $0.count == 1 })

    precondition(AudioPlaybackSchedule.frame(at: .nan, length: 100, sampleRate: 10) == 0)
    precondition(AudioPlaybackSchedule.frame(at: -.infinity, length: 100, sampleRate: 10) == 0)
    precondition(AudioPlaybackSchedule.frame(at: .infinity, length: 100, sampleRate: 10) == 100)
    precondition(AudioPlaybackSchedule.frame(at: 1.29, length: 100, sampleRate: 10) == 12)
    precondition(AudioPlaybackSchedule.frame(at: .greatestFiniteMagnitude, length: .max, sampleRate: 192_000) == .max)
    precondition(AudioPlaybackSchedule.frame(at: 1, length: .max, sampleRate: .nan) == 0)

    // An actual small PCM file supplies metadata; callback delivery is a fixture.
    let url = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("fixture.caf")
    let format = AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1)!
    let output = try AVAudioFile(forWriting: url, settings: format.settings)
    let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_000_001)!
    pcm.frameLength = pcm.frameCapacity
    memset(pcm.floatChannelData![0], 0, Int(pcm.frameLength) * MemoryLayout<Float>.size)
    try output.write(from: pcm)
    let file = try AVAudioFile(forReading: url)
    let fixture = PlaybackQueueFixture()
    try fixture.start(file)
    precondition(fixture.player.reservations.count == 2)
    let first = fixture.player.reservations[0]
    first.completion(.dataPlayedBack)
    await settle()
    precondition(fixture.player.reservations.count == 3)
    precondition(fixture.player.reservations[2].start == 960_000)
    precondition(fixture.player.reservations[2].count == 40_001)
    first.completion(.dataPlayedBack)
    await settle()
    precondition(fixture.player.reservations.count == 3)

    let stale = fixture.player.reservations[1]
    try fixture.start(file, at: 123)
    let restartedCount = fixture.player.reservations.count
    stale.completion(.dataPlayedBack)
    await settle()
    precondition(fixture.player.reservations.count == restartedCount)
    let active = fixture.player.reservations.last!
    fixture.playbackSchedule.cancel()
    active.completion(.dataPlayedBack)
    await settle()
    precondition(fixture.player.reservations.count == restartedCount)
    try fixture.start(file)
    let paused = fixture.player.reservations[fixture.player.reservations.count - 2]
    fixture.isPlaying = false
    paused.completion(.dataPlayedBack)
    await settle()
    precondition(fixture.player.reservations.count == restartedCount + 2)
    let ticker = PlaybackTickerFixture()
    await ticker.restartTicker()
    await settle()
    precondition(ticker.reads == 0, "Cancelled ticker touched replacement playback")
    try await Task.sleep(for: .milliseconds(220))
    precondition(ticker.reads == 1 && ticker.currentTime == 1)
    ticker.cancelTicker()
    await settle()
    precondition(ticker.reads == 1)
    try await SegmentedAudioPlaybackChecks.run(root: url.deletingLastPathComponent())
    print("PASS: 24h timelines at 5 sample rates, bounded reservations, overflow/seek bounds, production enqueue refill and stale/duplicate/paused callbacks, cancelled ticker restart")
  }

  static func settle() async {
    // Give the MainActor task launched by the production callback a chance to run.
    try? await Task.sleep(for: .milliseconds(20))
  }
}

@MainActor
final class PlaybackTickerFixture {
  var ticker: Task<Void, Never>?
  var isPlaying = true
  var currentTime: TimeInterval = 0
  var duration: TimeInterval = 10_000
  var reads = 0
  func elapsedTime() -> TimeInterval { reads += 1; return Double(reads) }
  func pause() { preconditionFailure("Unexpected end of fixture playback") }
  func seek(to time: TimeInterval) { preconditionFailure("Unexpected seek") }
}
