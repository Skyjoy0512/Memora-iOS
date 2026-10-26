import AVFAudio
import Foundation
import os

/// Owned by one serial AVAudioEngine input tap for its whole lifetime. Outputs
/// belong to SpeechAnalyzer, so reusing their storage would corrupt queued audio.
final class LiveAudioBufferConverter: @unchecked Sendable {
  private let sourceFormat: AVAudioFormat
  private let targetFormat: AVAudioFormat
  private let converter: AVAudioConverter?
  private let signposter = OSSignposter(subsystem: "app.memora.audio", category: "LiveConversion")
  /// Read only after the producer has stopped (or in a serial benchmark).
  private(set) var allocatedBufferCount = 0
  private(set) var inputBufferCount = 0

  init?(source: AVAudioFormat, target: AVAudioFormat) {
    guard source.sampleRate.isFinite, source.sampleRate > 0, source.channelCount > 0,
          target.sampleRate.isFinite, target.sampleRate > 0, target.channelCount > 0 else { return nil }
    sourceFormat = source
    targetFormat = target
    converter = source == target ? nil : AVAudioConverter(from: source, to: target)
    if source != target, converter == nil { return nil }
  }

  nonisolated func convert(_ input: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer? {
    let interval = signposter.isEnabled ? signposter.beginInterval("ConvertBuffer") : nil
    defer { if let interval { signposter.endInterval("ConvertBuffer", interval) } }
    inputBufferCount += 1
    guard input.format == sourceFormat else { throw CocoaError(.fileReadCorruptFile) }
    guard input.frameLength > 0 else { return nil }
    if let converter {
      let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * targetFormat.sampleRate / sourceFormat.sampleRate)) + 64
      guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
        throw CocoaError(.coderInvalidValue)
      }
      allocatedBufferCount += 1
      var supplied = false
      var error: NSError?
      let status = converter.convert(to: output, error: &error) { _, inputStatus in
        if supplied {
          inputStatus.pointee = .noDataNow
          return nil
        }
        supplied = true
        inputStatus.pointee = .haveData
        return input
      }
      if let error { throw error }
      guard status != .error else { throw CocoaError(.fileReadCorruptFile) }
      return output.frameLength > 0 ? output : nil
    }
    guard let copy = AVAudioPCMBuffer(pcmFormat: input.format, frameCapacity: input.frameLength) else {
      throw CocoaError(.coderInvalidValue)
    }
    allocatedBufferCount += 1
    copy.frameLength = input.frameLength
    let sourceBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input.audioBufferList))
    let destinationBuffers = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
    for index in sourceBuffers.indices {
      let source = sourceBuffers[index]
      guard let sourceData = source.mData, let destinationData = destinationBuffers[index].mData else {
        throw CocoaError(.fileReadCorruptFile)
      }
      memcpy(destinationData, sourceData, Int(source.mDataByteSize))
    }
    return copy
  }
}
