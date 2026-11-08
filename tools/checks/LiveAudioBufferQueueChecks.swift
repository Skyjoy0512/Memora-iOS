import AVFAudio
import Foundation

@main
enum LiveAudioBufferQueueChecks {
  static func main() async throws {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100,
      channels: 1, interleaved: false)!

    func buffer(_ value: Float, frames: AVAudioFrameCount = 4) -> AVAudioPCMBuffer {
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
      buffer.frameLength = frames
      for frame in 0..<Int(frames) { buffer.floatChannelData![0][frame] = value }
      return buffer
    }

    // The queue owns a copy: the tap may reuse its buffer as soon as enqueue
    // returns, and the consumer still sees the original samples.
    let queue = LiveAudioBufferQueue(capacity: 2)
    let input = buffer(0.25)
    precondition(queue.enqueue(input) == .enqueued)
    input.floatChannelData![0][0] = 0.9
    var iterator = queue.buffers.makeAsyncIterator()
    guard let first = await iterator.next() else { preconditionFailure("queued buffer was lost") }
    precondition(first.buffer.floatChannelData![0][0] == 0.25)
    queue.markConsumed()

    // Order is preserved while the bound holds.
    precondition(queue.enqueue(buffer(1)) == .enqueued)
    precondition(queue.enqueue(buffer(2)) == .enqueued)
    guard let second = await iterator.next(), let third = await iterator.next() else {
      preconditionFailure("ordered buffers were lost")
    }
    precondition(second.buffer.floatChannelData![0][0] == 1)
    precondition(third.buffer.floatChannelData![0][0] == 2)
    queue.markConsumed()
    queue.markConsumed()

    // A full queue drops the newest buffer instead of growing without bound.
    precondition(queue.enqueue(buffer(3)) == .enqueued)
    precondition(queue.enqueue(buffer(4)) == .enqueued)
    precondition(queue.enqueue(buffer(5)) == .dropped)
    precondition(queue.stats.enqueued == 5 && queue.stats.dropped == 1 && queue.stats.consumed == 3)

    // Finishing stops new input; already queued audio is still drainable.
    queue.finish()
    precondition(queue.enqueue(buffer(6)) == .closed)
    var drained = 0
    while await iterator.next() != nil { drained += 1 }
    precondition(drained == 2)
    queue.finish()

    // An empty buffer is not queued and is not counted as a drop.
    let emptyQueue = LiveAudioBufferQueue(capacity: 1)
    let empty = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4)!
    empty.frameLength = 0
    precondition(emptyQueue.enqueue(empty) == .ignored)
    precondition(emptyQueue.stats.enqueued == 0 && emptyQueue.stats.dropped == 0)

    print("LiveAudioBufferQueueChecks: passed (owned copy, order, bounded newest-drop, finish/closed, empty input; consumer conversion runs off the tap and is exercised in-app)")
  }
}
