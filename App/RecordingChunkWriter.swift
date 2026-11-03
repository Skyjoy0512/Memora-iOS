import AVFAudio
import Darwin
import Foundation
import Synchronization

/// A single producer supplies owned PCM through a bounded stream. No microphone
/// or session is acquired here; capture must stop when append returns false.
final class RecordingChunkWriter: @unchecked Sendable {
  enum Failure: Error, Sendable {
    case invalidInput, inputOverrun, storage, persistence, limit, changedFile, cancelled
  }

  struct Result: Sendable {
    var manifest: RecordingAudioManifest
    var writtenFrames: Int64
    var failure: Failure?
    var isComplete: Bool { failure == nil && manifest.finalizedDuration != nil }
  }

  static let maximumBufferedInputs = 16
  static let maximumBufferFrames: AVAudioFrameCount = 16_384
  private let accepting = Mutex(true)
  private let continuation: AsyncThrowingStream<OwnedBuffer, Error>.Continuation
  private let operation: Task<Result, Never>

  init(manifest: RecordingAudioManifest, directory: URL, partFrames: Int64 = 44_100 * 900,
       diagnostic: AudioDiagnosticSession? = nil,
       admitRotation: @escaping @Sendable (RecordingRotation) async -> Bool) throws {
    guard manifest.isValid(for: manifest.recordingID), manifest.parts.count == 1,
          manifest.parts[0].state == .writing, manifest.sampleRate == 44_100,
          partFrames > 0, partFrames <= 44_100 * 900,
          directory.isFileURL else { throw Failure.invalidInput }
    let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink != true else { throw Failure.invalidInput }
    let (stream, continuation) = AsyncThrowingStream<OwnedBuffer, Error>.makeStream(
      bufferingPolicy: .bufferingOldest(Self.maximumBufferedInputs))
    self.continuation = continuation
    operation = Task.detached(priority: .userInitiated) {
      let writer = Writer(manifest: manifest, directory: directory, partLimitFrames: partFrames,
        diagnostic: diagnostic, admitRotation: admitRotation)
      return await writer.run(stream)
    }
  }

  deinit {
    continuation.finish(throwing: CancellationError())
    operation.cancel()
  }

  /// Copies before returning: an AVAudioEngine tap reuses its own storage.
  @discardableResult
  func append(_ buffer: AVAudioPCMBuffer) -> Bool {
    accepting.withLock { accepts in
      guard accepts else { return false }
      do {
        guard buffer.frameLength > 0, buffer.frameLength <= Self.maximumBufferFrames,
              buffer.format.commonFormat == .pcmFormatFloat32, !buffer.format.isInterleaved,
              buffer.format.sampleRate == 44_100, buffer.format.channelCount == 1,
              let source = buffer.floatChannelData,
              let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength),
              let destination = copy.floatChannelData else { throw Failure.invalidInput }
        copy.frameLength = buffer.frameLength
        memcpy(destination[0], source[0], Int(buffer.frameLength) * MemoryLayout<Float>.size)
        switch continuation.yield(OwnedBuffer(buffer: copy)) {
        case .enqueued: return true
        case .dropped: throw Failure.inputOverrun
        case .terminated: accepts = false; return false
        @unknown default: throw Failure.inputOverrun
        }
      } catch {
        accepts = false
        continuation.finish(throwing: error)
        return false
      }
    }
  }

  /// The producer must first remove its tap; this drains every accepted input.
  func finish() async -> Result {
    accepting.withLock { value in value = false; continuation.finish() }
    return await operation.value
  }

  func cancel() {
    accepting.withLock { value in value = false; continuation.finish(throwing: CancellationError()) }
    operation.cancel()
  }

  private struct OwnedBuffer: @unchecked Sendable {
    var buffer: AVAudioPCMBuffer
  }

  /// This object is created inside, and owned only by, the consumer task.
  private final class Writer {
    var manifest: RecordingAudioManifest
    let directory: URL
    let partLimitFrames: Int64
    let diagnostic: AudioDiagnosticSession?
    let admitRotation: @Sendable (RecordingRotation) async -> Bool
    var file: AVAudioFile?
    var partFrames: Int64 = 0
    var writtenFrames: Int64 = 0
    var closedBytes: Int64 = 0
    var inputs = 0
    var isClosed = false

    init(manifest: RecordingAudioManifest, directory: URL, partLimitFrames: Int64, diagnostic: AudioDiagnosticSession?,
         admitRotation: @escaping @Sendable (RecordingRotation) async -> Bool) {
      self.manifest = manifest
      self.directory = directory
      self.partLimitFrames = partLimitFrames
      self.diagnostic = diagnostic
      self.admitRotation = admitRotation
    }

    func run(_ stream: AsyncThrowingStream<OwnedBuffer, Error>) async -> Result {
      do {
        for try await input in stream {
          try Task.checkCancellation()
          // Do not create an empty trailing file just because a recording ends
          // exactly on the boundary. Rotate only when the next sample arrives.
          if isClosed { try await rotate() }
          if file == nil { try openPart() }
          let buffer = input.buffer
          var position: AVAudioFrameCount = 0
          while position < buffer.frameLength {
            try Task.checkCancellation()
            if partFrames == partLimitFrames {
              try closePart()
              try await rotate()
              try openPart()
            }
            let remaining = partLimitFrames - partFrames
            let count = AVAudioFrameCount(min(Int64(buffer.frameLength - position), remaining))
            guard writtenFrames <= Int64(manifest.sampleRate) * 86_400 - Int64(count) else { throw Failure.limit }
            let slice = try slice(buffer, from: position, count: count)
            guard let file else { throw Failure.storage }
            try file.write(from: slice)
            position += count
            partFrames += Int64(count)
            writtenFrames += Int64(count)
          }
          inputs += 1
          if inputs.isMultiple(of: 256) { try checkCapacity() }
          if partFrames == partLimitFrames { try closePart() }
        }
        if !isClosed { try closePart() }
        guard writtenFrames > 0, manifest.finalizedDuration != nil else { throw Failure.invalidInput }
        return Result(manifest: manifest, writtenFrames: writtenFrames, failure: nil)
      } catch {
        // Releasing the writer flushes its container. Failure never seals an
        // unverified part or deletes any file; recovery re-inspects the draft.
        file = nil
        return Result(manifest: manifest, writtenFrames: writtenFrames,
          failure: error is CancellationError ? .cancelled : (error as? Failure ?? .storage))
      }
    }

    func openPart() throws {
      try Task.checkCancellation()
      try checkCapacity()
      let url = directory.appendingPathComponent(manifest.parts.last!.fileName)
      let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
      guard descriptor >= 0 else { throw Failure.storage }
      Darwin.close(descriptor)
      file = try AVAudioFile(forWriting: url, settings: [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: manifest.sampleRate,
        AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96_000,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
      ], commonFormat: .pcmFormatFloat32, interleaved: false)
      isClosed = false
    }

    func closePart() throws {
      guard file != nil, partFrames > 0 else { throw Failure.invalidInput }
      file = nil
      let url = directory.appendingPathComponent(manifest.parts.last!.fileName)
      let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
      guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
            let bytes = attributes.fileSize, bytes > 0,
            Int64(bytes) <= SourceMediaStaging.maximumInputBytes - closedBytes else { throw Failure.storage }
      let checked = try AVAudioFile(forReading: url)
      guard checked.length == partFrames, checked.processingFormat.sampleRate == Double(manifest.sampleRate),
            checked.processingFormat.channelCount == 1 else { throw Failure.changedFile }
      closedBytes += Int64(bytes)
      manifest.parts[manifest.parts.count - 1].frameCount = partFrames
      manifest.parts[manifest.parts.count - 1].state = .finalized
      isClosed = true
      diagnostic?.setAudioSeconds(Double(writtenFrames) / Double(manifest.sampleRate))
      diagnostic?.chunks(completed: manifest.parts.count)
    }

    func rotate() async throws {
      guard isClosed, manifest.parts.last?.state == .finalized else { throw Failure.invalidInput }
      var previous = manifest
      previous.parts[previous.parts.count - 1].state = .writing
      previous.parts[previous.parts.count - 1].frameCount = nil
      guard let transition = RecordingRotation.make(previous: previous, closedFrames: partFrames,
        nextFileName: "Memora-\(UUID().uuidString).m4a") else { throw Failure.limit }
      let span = diagnostic?.begin(.persistence)
      let admitted = await admitRotation(transition)
      diagnostic?.end(span, outcome: admitted ? .success : .failed)
      guard admitted else { throw Failure.persistence }
      manifest = transition.next
      partFrames = 0
      isClosed = false
      try Task.checkCancellation()
    }

    func checkCapacity() throws {
      guard try SourceMediaStaging.availableBytes(directory) >= SourceMediaStaging.minimumAvailableBytes else { throw Failure.storage }
      if let file {
        let bytes = try file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard Int64(bytes) <= SourceMediaStaging.maximumInputBytes - closedBytes else { throw Failure.limit }
      }
    }

    func slice(_ buffer: AVAudioPCMBuffer, from position: AVAudioFrameCount, count: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
      guard let slice = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: count),
            let source = buffer.floatChannelData, let destination = slice.floatChannelData else { throw Failure.invalidInput }
      slice.frameLength = count
      memcpy(destination[0], source[0].advanced(by: Int(position)), Int(count) * MemoryLayout<Float>.size)
      return slice
    }
  }
}
