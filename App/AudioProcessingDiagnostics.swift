import os
import Foundation
import Synchronization

/// Static signpost names contain no audio, transcript, record ID or credential.
enum AudioProcessingDiagnostics {
  static let signposter = OSSignposter(subsystem: "app.memora.audio", category: "Processing")
  static let enabledKey = "memora.audioDiagnostics.enabled"
  static let inspectSignalKey = "memora.audioDiagnostics.inspectSignal"
  private static let epoch = Mutex(UUID())
  private static let logger = Logger(subsystem: "app.memora.audio", category: "AudioMetrics")
  @TaskLocal static var current: AudioDiagnosticSession?

  static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
  static var inspectsSignal: Bool {
    isEnabled && (current?.snapshot.includesSignalInspection ?? UserDefaults.standard.bool(forKey: inspectSignalKey))
  }
  static var generation: UUID { epoch.withLock { $0 } }
  static func invalidateSessions() { epoch.withLock { $0 = UUID() } }

  static func begin(_ kind: AudioDiagnosticReport.Kind, audioSeconds: Double? = nil) -> AudioDiagnosticSession? {
    guard isEnabled else { return nil }
    let generation = generation
    let session = AudioDiagnosticSession(kind: kind, audioSeconds: audioSeconds, includesSignalInspection: inspectsSignal) { report in
      guard isEnabled, generation == Self.generation else { return }
      // Only a fixed-schema envelope is public to OSLog. Never interpolate a
      // URL, original ID, error, prompt or provider response here.
      logger.info("trace=\(report.id.uuidString, privacy: .public) kind=\(report.kind.rawValue, privacy: .public) state=\(report.outcome.rawValue, privacy: .public) elapsed=\(report.wallSeconds, privacy: .public) audio=\(report.audioSeconds ?? -1, privacy: .public) rtf=\(report.overallRTF ?? -1, privacy: .public) sampledPeakBytes=\(report.sampledPeakFootprintBytes ?? 0, privacy: .public) thermal=\(report.maximumThermalState, privacy: .public) reused=\(report.reusedChunks, privacy: .public) stage=\(report.events.last?.stage.rawValue ?? "none", privacy: .public) stageWall=\(report.events.last?.wallSeconds ?? -1, privacy: .public)")
      Task { await AudioDiagnosticArchive.shared.update(report, generation: generation) }
    }
    session.startSampling(interval: kind == .recording ? .seconds(15) : .seconds(5)) {
      isEnabled && generation == Self.generation
    }
    return session
  }

  static func trace<T>(_ kind: AudioDiagnosticReport.Kind, audioSeconds: Double? = nil,
                       operation: () async throws -> T,
                       outcome: (T) -> AudioDiagnosticReport.Outcome) async rethrows -> T {
    guard current == nil, let session = begin(kind, audioSeconds: audioSeconds) else { return try await operation() }
    do {
      let result = try await $current.withValue(session) { try await operation() }
      session.sample(await AudioResourceProbe.capture())
      session.finish(outcome(result))
      return result
    } catch {
      session.sample(await AudioResourceProbe.capture())
      session.finish(error is CancellationError ? .cancelled : .failed)
      throw error
    }
  }
}
