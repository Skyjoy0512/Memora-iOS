import AVFAudio
import Foundation

/// Only metadata spans the recording; readers exist for scheduled windows only.
final class AudioPlaybackSource {
  private var parts: [Part] = []
  private var scopedURL: URL?

  var format: AVAudioFormat { parts[0].format }
  var length: Int64 { parts.last!.end }
  var sampleRate: Double { format.sampleRate }
  var partEnds: [Int64] { parts.map(\.end) }

  init(_ input: AudioPlaybackInput) throws {
    let url = input.scopeURL
    guard url.isFileURL else { throw CocoaError(.fileReadCorruptFile) }
    let scoped = url.startAccessingSecurityScopedResource()
    do {
      switch input {
      case .file(let url):
        let part = try Self.inspect(url, offset: 0)
        parts = [part]
      case .parts(let manifest, let directory):
        guard manifest.isValid(for: manifest.recordingID), manifest.finalizedDuration != nil else {
          throw CocoaError(.fileReadCorruptFile)
        }
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw CocoaError(.fileReadCorruptFile) }
        for part in manifest.parts {
          let inspected = try Self.inspect(directory.appendingPathComponent(part.fileName), offset: part.frameOffset)
          guard let frames = part.frameCount, inspected.end - inspected.offset == frames,
                inspected.format.sampleRate == Double(manifest.sampleRate),
                (1...2).contains(inspected.format.channelCount),
                parts.first.map({ $0.format == inspected.format }) ?? true else {
            throw CocoaError(.fileReadCorruptFile)
          }
          parts.append(inspected)
        }
      }
      if scoped { scopedURL = url }
    } catch {
      if scoped { url.stopAccessingSecurityScopedResource() }
      throw error
    }
  }

  deinit { scopedURL?.stopAccessingSecurityScopedResource() }

  func resolve(_ segment: AudioPlaybackSchedule.Segment) throws -> (file: AVAudioFile, start: Int64) {
    guard segment.count > 0, let part = parts.first(where: { segment.start >= $0.offset && segment.start < $0.end }),
          Int64(segment.count) <= part.end - segment.start else { throw CocoaError(.fileReadCorruptFile) }
    let file = try Self.open(part.url)
    guard file.length == part.end - part.offset, file.processingFormat == part.format,
          try Self.attributes(part.url) == part.attributes else { throw CocoaError(.fileReadCorruptFile) }
    return (file, segment.start - part.offset)
  }

  private static func inspect(_ url: URL, offset: Int64) throws -> Part {
    let before = try attributes(url)
    let file = try open(url)
    guard offset >= 0, file.length <= Int64.max - offset, try attributes(url) == before else {
      throw CocoaError(.fileReadCorruptFile)
    }
    return Part(url: url, offset: offset, end: offset + file.length, format: file.processingFormat, attributes: before)
  }

  private static func open(_ url: URL) throws -> AVAudioFile {
    _ = try attributes(url)
    let file = try AVAudioFile(forReading: url)
    guard file.length > 0, file.processingFormat.sampleRate.isFinite,
          file.processingFormat.sampleRate > 0 else { throw CocoaError(.fileReadCorruptFile) }
    return file
  }

  private static func attributes(_ url: URL) throws -> Attributes {
    guard url.isFileURL else { throw CocoaError(.fileReadCorruptFile) }
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true, let bytes = values.fileSize, bytes > 0 else {
      throw CocoaError(.fileReadCorruptFile)
    }
    return Attributes(bytes: bytes, modified: values.contentModificationDate)
  }

  private struct Part {
    var url: URL
    var offset: Int64
    var end: Int64
    var format: AVAudioFormat
    var attributes: Attributes
  }

  private struct Attributes: Equatable {
    var bytes: Int
    var modified: Date?
  }
}
