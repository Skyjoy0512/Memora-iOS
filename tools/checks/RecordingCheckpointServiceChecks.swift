import Foundation

@main @MainActor
struct RecordingCheckpointServiceChecks {
  static func main() async {
    let continuous = RecordingCheckpointServiceFixture()
    let oldRun = continuous.run.runID!
    let lateFailure = Task { @MainActor in continuous.inputFailed(.conversion, runID: oldRun) }
    continuous.run.cancel(oldRun)
    let newRun = continuous.run.begin()!
    continuous.run.markRecording(newRun)
    let continuousMonitor = Task {}
    continuous.storageMonitor = continuousMonitor
    await lateFailure.value
    precondition(continuous.run.owns(newRun) && continuous.lastFailureReason == nil)
    precondition(continuous.microphone!.stops == 0 && !continuousMonitor.isCancelled && continuous.failures.isEmpty)
    precondition(continuous.diagnosticOutcome == .success)
    continuous.inputFailed(.overrun, runID: newRun)
    precondition(continuous.run.isFailure && continuous.microphone!.stops == 1 && continuousMonitor.isCancelled)
    precondition(continuous.failures.count == 1 && continuous.diagnosticOutcome == .failed)
    continuous.inputFailed(.noInput, runID: newRun)
    precondition(continuous.failures.count == 1 && continuous.microphone!.stops == 1)
    SourceMediaStaging.capacity = SourceMediaStaging.minimumAvailableBytes
    let healthy = RecordingCheckpointServiceFixture()
    let original = healthy.recorder!
    var calls = 0
    healthy.onCheckpoint = { calls += 1; return true }
    expect(await healthy.tick(original))
    precondition(calls == 1 && original.pauses == 0 && !healthy.hasReportedFailure)
    precondition(healthy.diagnostic.snapshot.audioSeconds == 86_400)
    let obsolete = RecorderCheckpointRecorderFixture()
    expect(await !healthy.tick(obsolete))
    precondition(calls == 1)

    for unavailable in [false, true] {
      let low = RecordingCheckpointServiceFixture()
      let recorder = low.recorder!
      low.onCheckpoint = { preconditionFailure("Low capacity wrote draft") }
      SourceMediaStaging.capacity = 0
      SourceMediaStaging.unavailable = unavailable
      expect(await !low.tick(recorder))
      precondition(recorder.pauses == 1 && low.hasReportedFailure && low.failures.count == 1)
      precondition(low.diagnostic.snapshot.counters["storageStop"] == 1)
      expect(await !low.tick(recorder))
      precondition(recorder.pauses == 1 && low.failures.count == 1)
    }
    SourceMediaStaging.unavailable = false
    SourceMediaStaging.capacity = SourceMediaStaging.minimumAvailableBytes
    let failed = RecordingCheckpointServiceFixture()
    let recorder = failed.recorder!
    let monitor = Task {}
    failed.storageMonitor = monitor
    failed.onCheckpoint = { false }
    expect(await !failed.tick(recorder))
    precondition(failed.hasReportedFailure && recorder.pauses == 1 && monitor.isCancelled && failed.storageMonitor == nil)
    precondition(failed.failures.count == 1 && failed.failures[0].contains("復旧情報"))
    precondition(failed.diagnostic.snapshot.counters["draftCheckpointFailure"] == 1 && failed.diagnosticOutcome == .failed)

    for change in 0..<3 {
      let service = RecordingCheckpointServiceFixture()
      let oldRecorder = service.recorder!
      let gate = RecordingRecoveryGate<Bool>()
      service.onCheckpoint = { await gate.wait() }
      let operation = Task { await service.tick(oldRecorder) }
      await gate.entered()
      let replacement = RecorderCheckpointRecorderFixture()
      switch change {
      case 0: service.recorder = nil
      case 1: service.recorder = replacement
      default: operation.cancel()
      }
      gate.resume(false)
      expect(await !operation.value)
      precondition(oldRecorder.pauses == 0 && replacement.pauses == 0 && !service.hasReportedFailure)
      precondition(service.failures.isEmpty && service.diagnostic.snapshot.counters["draftCheckpointFailure"] == nil)
    }
    print("RecordingCheckpointServiceChecks: PASS. Production storage/checkpoint/stop policy; low/unknown capacity, async checkpoint failure, single pause/notification, cancelled monitor, 24h duration counter, stale recorder identity, cancelled callback and obsolete continuous-run failure refusal. Recorder/OS/capacity services are fixtures; timer scheduling and actual microphone are not exercised.")
  }
  static func expect(_ value: Bool) { precondition(value) }
}

@MainActor final class RecordingCheckpointServiceFixture {
  var recorder: RecorderCheckpointRecorderFixture? = .init()
  var microphone: RecordingMicrophoneInput? = .init()
  var recordedDuration: TimeInterval? = 86_400
  var run = RecordingRunCoordinator()
  var lastFailureReason: String?
  var hasReportedFailure: Bool { run.isFailure }
  var storageMonitor: Task<Void, Never>?
  var diagnostic: AudioDiagnosticSession! = AudioDiagnosticSession(kind: .recording) { _ in }
  var diagnosticOutcome = AudioDiagnosticReport.Outcome.success
  var onCheckpoint: (() async -> Bool)?
  var failures: [String] = []
  var onInterruption: ((RecorderCheckpointEventFixture) -> Void)? {
    { [weak self] event in if case .failed(let reason) = event { self?.failures.append(reason) } }
  }

  init() {
    if let id = run.begin() { run.markRecording(id) }
  }
}

final class RecorderCheckpointRecorderFixture {
  var url = URL(fileURLWithPath: "/fixture/recording.m4a")
  var pauses = 0
  func pause() { pauses += 1 }
}

enum RecorderCheckpointEventFixture { case failed(String) }

final class RecordingMicrophoneInput {
  enum Failure { case noInput, unsupportedFormat, conversion, inputGap, inputDuplicate, overrun }
  var stops = 0
  func stop() { stops += 1 }
}

@MainActor enum SourceMediaStaging {
  static let minimumAvailableBytes: Int64 = 256 * 1024 * 1024
  static var capacity = minimumAvailableBytes
  static var unavailable = false
  static func availableBytes(_ directory: URL) throws -> Int64 {
    if unavailable { throw CocoaError(.fileReadUnknown) }
    return capacity
  }
}
