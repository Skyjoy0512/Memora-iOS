import AVFoundation
import Foundation

/// Configuration is immutable once export starts. Only AVFoundation's
/// cancellation API may touch the session concurrently with its async export.
final class SourceMediaAudioExport: @unchecked Sendable {
  static let maximumOutputBytes: Int64 = 100 * 1_024 * 1_024
  private let session: AVAssetExportSession

  init?(asset: AVAsset, temporaryDirectory: URL) {
    guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { return nil }
    session.directoryForTemporaryFiles = temporaryDirectory
    self.session = session
  }

  func write(to output: URL, stageDirectory: URL) async throws {
    try Task.checkCancellation()
    try await withThrowingTaskGroup(of: Bool.self) { group in
      group.addTask { [self] in
        try await withTaskCancellationHandler {
          try Task.checkCancellation()
          try await session.export(to: output, as: .m4a)
          try Task.checkCancellation()
        } onCancel: { [self] in cancelLegacyExport() }
        return true
      }
      group.addTask {
        while true {
          try Task.checkCancellation()
          if FileManager.default.fileExists(atPath: output.path) {
            let values = try output.resourceValues(forKeys: [.fileSizeKey])
            guard Int64(values.fileSize ?? 0) <= Self.maximumOutputBytes else { throw SourceMediaFailure.exportTooLarge }
          }
          guard try SourceMediaStaging.size(of: stageDirectory) <= SourceMediaStaging.maximumStageBytes else {
            throw SourceMediaFailure.exportTooLarge
          }
          guard try SourceMediaStaging.size(of: stageDirectory.deletingLastPathComponent()) <= SourceMediaStaging.maximumTotalBytes else {
            throw SourceMediaFailure.stagingLimit
          }
          try await Task.sleep(for: .milliseconds(200))
        }
      }
      defer { group.cancelAll() }
      _ = try await group.next()
    }
    try Task.checkCancellation()
    try Self.validateOutput(output, stageDirectory: stageDirectory)
  }

  static func validateOutput(_ output: URL, stageDirectory: URL) throws {
    let values = try output.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true, let bytes = values.fileSize, bytes > 0 else {
      throw SourceMediaFailure.invalidTemporaryFile
    }
    guard bytes <= maximumOutputBytes,
          try SourceMediaStaging.size(of: stageDirectory) <= SourceMediaStaging.maximumStageBytes else {
      throw SourceMediaFailure.exportTooLarge
    }
    guard try SourceMediaStaging.size(of: stageDirectory.deletingLastPathComponent()) <= SourceMediaStaging.maximumTotalBytes else {
      throw SourceMediaFailure.stagingLimit
    }
  }

  private func cancelLegacyExport() {
    if #available(iOS 27.0, macOS 27.0, tvOS 27.0, visionOS 27.0, *) {
      // Async export observes its task's cancellation on these SDK releases.
    } else {
      session.cancelExport()
    }
  }
}
