import Foundation

/// Keeps only two short reservations, regardless of the recording's length.
struct AudioPlaybackSchedule {
  struct Segment: Equatable, Sendable {
    var generation: UUID
    var start: Int64
    var count: UInt32
  }

  private var generation = UUID()
  private var nextFrame: Int64 = 0
  private var totalFrames: Int64 = 0
  private var windowFrames: UInt32 = 0
  private var outstanding: Set<Int64> = []
  private var partEnds: [Int64] = []

  mutating func start(at frame: Int64, length: Int64, sampleRate: Double, partEnds: [Int64] = []) -> [Segment] {
    cancel()
    guard length > 0, frame >= 0, frame < length,
          sampleRate.isFinite, sampleRate > 0 else { return [] }
    if !partEnds.isEmpty {
      guard partEnds.count <= RecordingAudioManifest.maximumParts, partEnds.last == length else { return [] }
      var previous: Int64 = 0
      for end in partEnds {
        guard end > previous else { return [] }
        previous = end
      }
    }
    self.partEnds = partEnds
    totalFrames = length
    nextFrame = frame
    // Clamp before converting: even malformed format metadata cannot trap.
    windowFrames = UInt32(max(1, min(Double(UInt32.max), sampleRate * 60)))
    return (0..<2).compactMap { _ in reserveNext() }
  }

  mutating func complete(_ segment: Segment) -> Segment? {
    guard contains(segment) else { return nil }
    outstanding.remove(segment.start)
    return reserveNext()
  }

  func contains(_ segment: Segment) -> Bool {
    segment.generation == generation && outstanding.contains(segment.start)
  }

  mutating func cancel() {
    generation = UUID()
    nextFrame = 0
    totalFrames = 0
    windowFrames = 0
    outstanding.removeAll(keepingCapacity: true)
    partEnds.removeAll(keepingCapacity: true)
  }

  private mutating func reserveNext() -> Segment? {
    guard nextFrame < totalFrames, windowFrames > 0, outstanding.count < 2 else { return nil }
    let end = partEnds.first(where: { $0 > nextFrame }) ?? totalFrames
    let count = UInt32(min(Int64(windowFrames), end - nextFrame))
    let segment = Segment(generation: generation, start: nextFrame, count: count)
    outstanding.insert(nextFrame)
    nextFrame += Int64(count)
    return segment
  }

  static func frame(at time: TimeInterval, length: Int64, sampleRate: Double) -> Int64 {
    guard length > 0, sampleRate.isFinite, sampleRate > 0, !time.isNaN, time > 0 else { return 0 }
    let position = time * sampleRate
    // Double(Int64.max) rounds up, so conversion must follow this comparison.
    guard position < Double(length) else { return length }
    return Int64(position)
  }
}
