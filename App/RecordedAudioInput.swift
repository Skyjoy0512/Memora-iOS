import AVFoundation
import CryptoKit
import Foundation

enum RecordedAudioInput: Sendable {
  case file(URL)
  case parts(RecordingAudioManifest, directory: URL)

  struct Prepared {
    var asset: AVAsset
    var snapshots: [SourceMediaSnapshot]
    var duration: TimeInterval
    var fingerprint: String
    var suffix: String
    var pipeline: String
  }

  func byteCount() throws -> Int64 {
    var total: Int64 = 0
    for url in try originals() {
      let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
      guard values.isRegularFile == true, values.isSymbolicLink != true,
            let bytes = values.fileSize, bytes > 0 else { throw SourceMediaFailure.invalidTemporaryFile }
      guard Int64(bytes) <= SourceMediaStaging.maximumInputBytes - total else { throw SourceMediaFailure.stagingLimit }
      total += Int64(bytes)
    }
    return total
  }

  func prepare(in directory: URL) async throws -> Prepared {
    let urls = try originals()
    switch self {
    case .file(let url):
      let snapshot = try Self.snapshot(url, in: directory, stageDirectory: directory)
      let asset = AVURLAsset(url: snapshot.url)
      return Prepared(asset: asset, snapshots: [snapshot], duration: try await asset.load(.duration).seconds,
        fingerprint: snapshot.fingerprint, suffix: url.pathExtension.lowercased(), pipeline: "recording-speech-analyzer-v1")

    case .parts(let manifest, _):
      guard let duration = manifest.finalizedDuration else { throw SourceMediaFailure.invalidDuration }
      // Keep the composition itself alive; its tracks hold references to the
      // snapshots, and only the current 15-minute export is materialized.
      let composition = AVMutableComposition()
      guard let destination = composition.addMutableTrack(withMediaType: .audio,
        preferredTrackID: kCMPersistentTrackID_Invalid) else { throw SourceMediaFailure.invalidTemporaryFile }
      var snapshots: [SourceMediaSnapshot] = []
      var descriptor = [["manifest-v1", String(manifest.sampleRate)]]
      var channelCount: AVAudioChannelCount?
      for (index, part) in manifest.parts.enumerated() {
        try Task.checkCancellation()
        let folder = directory.appendingPathComponent("part-\(index)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let snapshot = try Self.snapshot(urls[index], in: folder, stageDirectory: directory)
        snapshots.append(snapshot)
        let audio = try AVAudioFile(forReading: snapshot.url)
        guard let frames = part.frameCount, audio.length == frames,
              audio.processingFormat.sampleRate == Double(manifest.sampleRate),
              (1...2).contains(audio.processingFormat.channelCount),
              channelCount == nil || channelCount == audio.processingFormat.channelCount else {
          throw SourceMediaFailure.invalidDuration
        }
        channelCount = audio.processingFormat.channelCount
        let asset = AVURLAsset(url: snapshot.url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard tracks.count == 1, let source = tracks.first else { throw SourceMediaFailure.invalidTemporaryFile }
        let available = try await source.load(.timeRange)
        let length = CMTime(value: frames, timescale: Int32(manifest.sampleRate))
        guard CMTimeCompare(available.start, .zero) == 0,
              CMTimeCompare(available.duration, length) >= 0 else { throw SourceMediaFailure.invalidDuration }
        try destination.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: source,
          at: CMTime(value: part.frameOffset, timescale: Int32(manifest.sampleRate)))
        descriptor.append([snapshot.fingerprint, String(part.frameOffset), String(frames)])
      }
      let last = manifest.parts.last!
      let expected = CMTime(value: last.frameOffset + last.frameCount!, timescale: Int32(manifest.sampleRate))
      guard CMTimeCompare(composition.duration, expected) == 0 else { throw SourceMediaFailure.invalidDuration }
      let fingerprint = SHA256.hash(data: try JSONEncoder().encode(descriptor)).map { String(format: "%02x", $0) }.joined()
      return Prepared(asset: composition, snapshots: snapshots, duration: duration, fingerprint: fingerprint,
        suffix: "manifest", pipeline: "recording-manifest-speech-analyzer-v1")
    }
  }

  private static func snapshot(_ url: URL, in directory: URL, stageDirectory: URL) throws -> SourceMediaSnapshot {
    let used = try SourceMediaStaging.size(of: stageDirectory)
    let values = try url.resourceValues(forKeys: [.fileSizeKey])
    guard let bytes = values.fileSize, bytes > 0,
          Int64(bytes) <= SourceMediaStaging.maximumInputBytes - used else { throw SourceMediaFailure.stagingLimit }
    guard try SourceMediaStaging.availableBytes(stageDirectory) >= SourceMediaStaging.minimumAvailableBytes + Int64(bytes) else {
      throw SourceMediaFailure.capacity
    }
    // A file growing after admission cannot exceed this reservation or consume
    // another part's disk budget while its immutable copy is being made.
    return try SourceMediaSnapshot(url, directory: directory, maximumBytes: bytes)
  }

  private func originals() throws -> [URL] {
    switch self {
    case .file(let url):
      guard url.isFileURL else { throw SourceMediaFailure.invalidTemporaryFile }
      return [url]
    case .parts(let manifest, let directory):
      guard directory.isFileURL, manifest.isValid(for: manifest.recordingID), manifest.finalizedDuration != nil else {
        throw SourceMediaFailure.invalidDuration
      }
      let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      guard values.isDirectory == true, values.isSymbolicLink != true else { throw SourceMediaFailure.invalidTemporaryFile }
      return manifest.fileNames.map { directory.appendingPathComponent($0) }
    }
  }
}
