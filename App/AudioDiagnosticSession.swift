import Foundation
import Synchronization

final class AudioDiagnosticSession: Sendable {
  private struct OpenSpan: Sendable {
    var stage: AudioDiagnosticReport.Stage
    var start: Double
    var audioSeconds: Double?
  }
  private struct State: Sendable {
    var report: AudioDiagnosticReport
    var open: [UUID: OpenSpan] = [:]
    var sampler: Task<Void, Never>?
  }
  private let state: Mutex<State>
  private let now: @Sendable () -> Double
  private let sink: @Sendable (AudioDiagnosticReport) -> Void

  init(kind: AudioDiagnosticReport.Kind, audioSeconds: Double? = nil, includesSignalInspection: Bool = false,
       environment: AudioDiagnosticEnvironment = .current,
       now: (@Sendable () -> Double)? = nil,
       sink: @escaping @Sendable (AudioDiagnosticReport) -> Void) {
    let origin = ContinuousClock.now
    self.now = now ?? {
      let elapsed = origin.duration(to: .now).components
      return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    }
    self.sink = sink
    state = Mutex(State(report: .init(id: UUID(), kind: kind, environment: environment,
      includesSignalInspection: includesSignalInspection)))
    setAudioSeconds(audioSeconds)
  }

  func startSampling(interval: Duration, whileEnabled: @escaping @Sendable () -> Bool) {
    let id = snapshot.id
    let task = Task { [weak self] in
      await AudioResourceProbe.acquireBattery(id)
      while !Task.isCancelled, whileEnabled(), self != nil {
        self?.sample(await AudioResourceProbe.capture())
        do { try await Task.sleep(for: interval) } catch { break }
      }
      await AudioResourceProbe.releaseBattery(id)
    }
    state.withLock { value in
      if value.report.outcome == .running { value.sampler = task }
      else { task.cancel() }
    }
  }

  func begin(_ stage: AudioDiagnosticReport.Stage, audioSeconds: Double? = nil) -> UUID {
    let token = UUID(), elapsed = max(0, now())
    update { value in
      guard value.open.count < 32 else { return }
      value.open[token] = .init(stage: stage, start: elapsed, audioSeconds: validDuration(audioSeconds))
      append(.init(stage: stage, elapsedSeconds: elapsed, audioSeconds: validDuration(audioSeconds), outcome: .running), to: &value.report)
    }
    return token
  }

  func end(_ token: UUID?, outcome: AudioDiagnosticReport.Outcome) {
    guard let token else { return }
    let elapsed = max(0, now())
    update { value in
      guard let span = value.open.removeValue(forKey: token) else { return }
      close(span, at: elapsed, outcome: outcome, report: &value.report)
    }
  }

  func setAudioSeconds(_ seconds: Double?) {
    guard let seconds = validDuration(seconds) else { return }
    update { $0.report.audioSeconds = seconds }
  }

  func setEngine(_ engine: AudioDiagnosticReport.Engine) { update { $0.report.engine = engine } }
  func chunks(reused: Int? = nil, completed: Int? = nil) {
    update {
      if let reused { $0.report.reusedChunks = max(0, reused) }
      if let completed { $0.report.completedChunks = max(0, completed) }
    }
  }
  func signal(_ report: AudioSignalReport) {
    guard report.isValid else { return }
    update {
      if $0.report.signals.count == 128 { $0.report.signals.removeFirst() }
      $0.report.signals.append(report)
    }
  }
  func count(_ counter: AudioDiagnosticReport.Counter) {
    update { $0.report.counters[counter.rawValue, default: 0] += 1 }
  }

  func sample(_ resource: AudioDiagnosticReport.Resources) {
    var sample = resource
    sample.elapsedSeconds = max(0, now())
    update { value in
      if value.report.samples.count == 256 { value.report.samples.remove(at: 1); value.report.omittedSamples += 1 }
      value.report.samples.append(sample)
      if let memory = sample.footprintBytes {
        value.report.sampledPeakFootprintBytes = max(value.report.sampledPeakFootprintBytes ?? 0, memory)
      }
      if value.report.firstBatteryFraction == nil { value.report.firstBatteryFraction = sample.batteryFraction }
      if let battery = sample.batteryFraction { value.report.lastBatteryFraction = battery }
      value.report.maximumThermalState = max(value.report.maximumThermalState, sample.thermalState)
    }
  }

  func finish(_ outcome: AudioDiagnosticReport.Outcome) {
    let elapsed = max(0, now())
    let result: (AudioDiagnosticReport, Task<Void, Never>?)? = state.withLock { value in
      guard value.report.outcome == .running else { return nil }
      for span in value.open.values { close(span, at: elapsed, outcome: outcome, report: &value.report) }
      value.open = [:]
      value.report.wallSeconds = elapsed
      value.report.outcome = outcome
      value.report.revision += 1
      let sampler = value.sampler
      value.sampler = nil
      return (value.report, sampler)
    }
    guard let result else { return }
    result.1?.cancel()
    sink(result.0)
  }

  var snapshot: AudioDiagnosticReport { state.withLock { $0.report } }

  private func update(_ change: (inout State) -> Void) {
    let report = state.withLock { value -> AudioDiagnosticReport? in
      guard value.report.outcome == .running else { return nil }
      change(&value)
      value.report.wallSeconds = max(0, now())
      value.report.revision += 1
      return value.report
    }
    if let report { sink(report) }
  }

  private func validDuration(_ value: Double?) -> Double? { value.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } }
  private func append(_ event: AudioDiagnosticReport.Event, to report: inout AudioDiagnosticReport) {
    if report.events.count == 256 { report.events.remove(at: 1); report.omittedEvents += 1 }
    report.events.append(event)
  }
  private func close(_ span: OpenSpan, at elapsed: Double, outcome: AudioDiagnosticReport.Outcome,
                     report: inout AudioDiagnosticReport) {
    let wall = max(0, elapsed - span.start)
    let audio = span.audioSeconds ?? (span.stage == .quality && outcome == .success ? report.signals.last?.duration : nil)
    append(.init(stage: span.stage, elapsedSeconds: elapsed, wallSeconds: wall,
      audioSeconds: audio, outcome: outcome), to: &report)
    var total = report.totals[span.stage.rawValue, default: .init()]
    total.calls += 1
    total.wallSeconds += wall
    total.audioSeconds += audio ?? 0
    if outcome == .success || outcome == .empty {
      total.successfulAudioSeconds += audio ?? 0
      total.successfulWallSeconds += wall
      total.successfulCalls += 1
    }
    report.totals[span.stage.rawValue] = total
  }
}
