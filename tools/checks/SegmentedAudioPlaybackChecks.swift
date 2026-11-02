import AVFAudio
import Foundation

enum SegmentedAudioPlaybackChecks {
  @MainActor
  static func run(root: URL) async throws {
    let folder = root.appendingPathComponent("playback-parts", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    var parts: [RecordingAudioPart] = []
    var offset: Int64 = 0
    for (index, frames) in [480_123, 960_005, 240_001].enumerated() {
      let name = "part-\(index).caf"
      try write(folder.appendingPathComponent(name), frames: frames)
      parts.append(.init(fileName: name, frameOffset: offset, frameCount: Int64(frames), state: .finalized))
      offset += Int64(frames)
    }
    let manifest = RecordingAudioManifest(recordingID: UUID(), sampleRate: 8_000, parts: parts)
    let input = AudioPlaybackInput.parts(manifest, directory: folder)
    let source = try AudioPlaybackSource(input)
    precondition(source.length == offset && source.partEnds == parts.map { $0.frameOffset + $0.frameCount! })
    let fixture = PlaybackQueueFixture()
    try fixture.start(input: input)
    var index = 0
    var cursor: Int64 = 0
    while index < fixture.player.reservations.count {
      precondition(fixture.scheduledFiles.count <= 2)
      let reservation = fixture.player.reservations[index]
      let part = parts.first { cursor >= $0.frameOffset && cursor < $0.frameOffset + $0.frameCount! }!
      precondition(reservation.file.url.lastPathComponent == part.fileName)
      precondition(reservation.start == cursor - part.frameOffset)
      precondition(reservation.start + Int64(reservation.count) <= part.frameCount!)
      cursor += Int64(reservation.count)
      reservation.completion(.dataPlayedBack)
      await AudioPlaybackChecks.settle()
      let count = fixture.player.reservations.count
      reservation.completion(.dataPlayedBack)
      await AudioPlaybackChecks.settle()
      precondition(count == fixture.player.reservations.count)
      index += 1
    }
    precondition(cursor == source.length && fixture.scheduledFiles.isEmpty && fixture.failures == 0)

    try fixture.start(input: input, at: parts[1].frameOffset + 100)
    let seekStart = fixture.player.reservations[fixture.player.reservations.count - 2]
    precondition(seekStart.start == 100 && seekStart.file.url.lastPathComponent == parts[1].fileName)
    try fixture.start(input: input, at: parts[1].frameOffset + 100)
    let count = fixture.player.reservations.count
    seekStart.completion(.dataPlayedBack)
    await AudioPlaybackChecks.settle()
    precondition(count == fixture.player.reservations.count && fixture.scheduledFiles.count == 2)

    var unsealed = manifest
    unsealed.parts[2].state = .writing; unsealed.parts[2].frameCount = nil
    try refuse(.parts(unsealed, directory: folder))
    var wrongFrames = manifest
    wrongFrames.parts[2].frameCount! -= 1
    try refuse(.parts(wrongFrames, directory: folder))
    let link = folder.appendingPathComponent("link.caf")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder.appendingPathComponent(parts[0].fileName))
    var linked = manifest; linked.parts[0].fileName = link.lastPathComponent
    try refuse(.parts(linked, directory: folder))

    let changing = PlaybackQueueFixture()
    try changing.start(input: input)
    let nextFile = folder.appendingPathComponent(parts[1].fileName)
    let handle = try FileHandle(forWritingTo: nextFile)
    try handle.truncate(atOffset: 1); try handle.close()
    changing.player.reservations[0].completion(.dataPlayedBack)
    await AudioPlaybackChecks.settle()
    precondition(changing.failures == 1 && !changing.isPlaying && changing.scheduledFiles.isEmpty)
    try refuse(input)

    var schedule = AudioPlaybackSchedule()
    let rate = 96_000.0
    let length = Int64(rate * 86_400)
    let ends = (1...96).map { Int64($0) * Int64(rate * 900) }
    var pending = schedule.start(at: 0, length: length, sampleRate: rate, partEnds: ends)
    cursor = 0
    while !pending.isEmpty {
      precondition(pending.count <= 2)
      let segment = pending.removeFirst()
      precondition(segment.start == cursor)
      cursor += Int64(segment.count)
      precondition(cursor <= ends.first(where: { $0 > segment.start })!)
      if let next = schedule.complete(segment) { pending.append(next) }
    }
    precondition(cursor == length)
    for invalid in [[Int64(0), length], [length, length], [length - 1]] {
      precondition(schedule.start(at: 0, length: length, sampleRate: rate, partEnds: invalid).isEmpty)
    }
    print("PASS: multipart native readers, bounded cross-file reservations, seek mapping, stale/duplicate callbacks, changed/missing/invalid inputs, 24h/96-part frame planning. Audio output is a fixture.")
  }

  private static func refuse(_ input: AudioPlaybackInput) throws {
    do { _ = try AudioPlaybackSource(input) }
    catch { return }
    preconditionFailure("Invalid playback input accepted")
  }

  private static func write(_ url: URL, frames: Int) throws {
    let format = AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1)!
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096)!
    memset(buffer.floatChannelData![0], 0, 4_096 * MemoryLayout<Float>.size)
    var remaining = frames
    while remaining > 0 {
      buffer.frameLength = AVAudioFrameCount(min(4_096, remaining))
      try file.write(from: buffer)
      remaining -= Int(buffer.frameLength)
    }
  }
}
