import Foundation

/// Host overlap checks cannot establish iPhone memory, thermal or recording
/// safety. Production keeps sequential preparation until that review exists.
struct RecordedAudioPreparationPolicy: Sendable {
  static let validated = Self(allowsOverlap: false)
  private var allowsOverlap: Bool
  private var resources: @Sendable (URL) throws -> Resources = { try Resources.read($0) }

  func shouldPrepareNext(in directory: URL) -> Bool {
    guard allowsOverlap, !Task.isCancelled else { return false }
    return (try? resources(directory).permitsLookahead) ?? false
  }

  #if MEMORA_HOST_CHECKS
  static func candidate(resources: @escaping @Sendable (URL) throws -> Resources = { try Resources.read($0) }) -> Self {
    Self(allowsOverlap: true, resources: resources)
  }
  #endif

  struct Resources: Sendable {
    var stageBytes: Int64
    var totalBytes: Int64
    var availableBytes: Int64
    var lowPower: Bool
    var thermal: ProcessInfo.ThermalState

    var permitsLookahead: Bool {
      let next = SourceMediaAudioExport.maximumOutputBytes
      guard !lowPower, thermal == .nominal, stageBytes >= 0, totalBytes >= stageBytes,
            stageBytes <= SourceMediaStaging.maximumStageBytes - next,
            totalBytes <= SourceMediaStaging.maximumTotalBytes - next,
            availableBytes >= SourceMediaStaging.minimumAvailableBytes + next else { return false }
      return true
    }

    static func read(_ directory: URL) throws -> Self {
      try Task.checkCancellation()
      let info = ProcessInfo.processInfo
      return try Self(stageBytes: SourceMediaStaging.size(of: directory),
        totalBytes: SourceMediaStaging.size(of: directory.deletingLastPathComponent()),
        availableBytes: SourceMediaStaging.availableBytes(directory),
        lowPower: info.isLowPowerModeEnabled, thermal: info.thermalState)
    }
  }
}
