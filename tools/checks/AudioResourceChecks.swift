import AVFAudio
import Darwin
import Foundation

@main
enum AudioResourceChecks {
  static func main() async throws {
    let minutes = Int(CommandLine.arguments.dropFirst().first ?? "15")!
    let started = Date()
    let cpuStarted = cpuSeconds()
    #if BASELINE
    var finalized: [String] = []
    #else
    var history = LiveTranscriptHistory()
    for mode in RecordingPowerMode.allCases {
      for lowPower in [false, true] {
        for thermal in [false, true] {
          precondition(RecordingPowerMode.conservesResources(mode: mode, lowPower: lowPower,
            thermalRestricted: thermal) == (mode == .lowPower || lowPower || thermal))
        }
      }
    }
    #endif
    // Virtual duration, one independently owned display result per second.
    // This measures storage, not recognition quality or real recording energy.
    for second in 0..<(minutes * 60) {
      let text = "\(second): " + String(repeating: "検証用の確定文。録音した原文は別に保存します。", count: 8)
      #if BASELINE
      finalized.append(text)
      #else
      history.append(text)
      precondition(history.lines.count <= LiveTranscriptHistory.maximumLines)
      #endif
    }
    #if BASELINE
    let retainedLines = finalized.count
    let retainedBytes = finalized.reduce(0) { $0 + $1.utf8.count }
    #else
    precondition(history.totalLines == minutes * 60 && history.hasTrimmedHistory)
    precondition(history.lines.last?.id == minutes * 60 - 1)
    let retainedLines = history.lines.count
    let retainedBytes = history.lines.reduce(0) { $0 + $1.text.utf8.count }
    var adversarial = LiveTranscriptHistory()
    adversarial.append(String(repeating: "a\u{301}", count: 50_000))
    precondition(adversarial.lines[0].text.utf8.count <= LiveTranscriptHistory.maximumUTF8BytesPerLine + 3)
    #endif

    let source = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    let target = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    let converter = LiveAudioBufferConverter(source: source, target: target)!
    let passthrough = LiveAudioBufferConverter(source: source, target: source)!
    let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 4_096)!
    input.frameLength = 4_096
    for frame in 0..<Int(input.frameLength) { input.floatChannelData![0][frame] = sin(Float(frame) * 0.05) * 0.1 }
    let copied = try passthrough.convert(input)!
    let savedSample = copied.floatChannelData![0][10]
    input.floatChannelData![0][10] = 0.9
    precondition(copied.floatChannelData![0][10] == savedSample, "tap storage escaped without ownership")
    input.floatChannelData![0][10] = savedSample
    let count = Int(ceil(Double(minutes * 60) * source.sampleRate / 4_096))
    var retained: [AVAudioPCMBuffer] = []
    var maximumFrames: AVAudioFrameCount = 0
    for _ in 0..<count {
      try autoreleasepool {
        if let output = try converter.convert(input) {
          precondition(output.format == target && output.frameLength > 0)
          precondition(!retained.contains { $0 === output }, "queued audio was overwritten")
          maximumFrames = max(maximumFrames, output.frameLength)
          retained.append(output)
          if retained.count > 16 { retained.removeFirst() }
        }
      }
    }
    #if !BASELINE
    precondition(converter.allocatedBufferCount == count && converter.inputBufferCount == count)
    #endif
    let (queue, continuation) = AsyncThrowingStream<Int, Error>.makeStream(bufferingPolicy: .bufferingNewest(16))
    for value in 0..<16 {
      guard case .enqueued = continuation.yield(value) else { fatalError("early overflow") }
    }
    guard case .dropped = continuation.yield(16) else { fatalError("queue was not bounded") }
    continuation.finish(throwing: CocoaError(.coderInvalidValue))
    var drained = 0
    do { for try await _ in queue { drained += 1 } } catch { }
    precondition(drained <= 16)
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let result: [String: Any] = ["virtualMinutes": minutes, "retainedLines": retainedLines,
      "retainedUTF8Bytes": retainedBytes, "convertedBuffers": count,
      "maximumOutputFrames": maximumFrames, "queueCapacity": 16,
      "wallSeconds": Date().timeIntervalSince(started), "cpuSeconds": cpuSeconds() - cpuStarted,
      "peakRSSBytes": usage.ru_maxrss, "realTimeRecording": false,
      "batteryMeasured": false, "recognitionQualityMeasured": false]
    print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), encoding: .utf8)!)
  }

  static func cpuSeconds() -> Double {
    var time = timespec()
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &time)
    return Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000
  }
}
