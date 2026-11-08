import Foundation
import Synchronization

@main struct AudioDiagnosticChecks {
  static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let clock = MetricClock()
    let latest = Mutex<AudioDiagnosticReport?>(nil)
    let session = AudioDiagnosticSession(kind: .recordedTranscription, audioSeconds: 3600,
      now: { clock.value }) { report in latest.withLock { $0 = report } }
    let queue = session.begin(.queue)
    clock.set(10)
    session.end(queue, outcome: .success)
    let recognition = session.begin(.recognition, audioSeconds: 60)
    clock.set(16)
    session.end(recognition, outcome: .success)
    session.end(recognition, outcome: .success)
    session.chunks(reused: 3, completed: 4)
    clock.set(20)
    session.finish(.success)
    let report = session.snapshot
    precondition(report.isValid && report.totals["recognition"]?.calls == 1)
    precondition(report.totals["recognition"]?.rtf == 0.1 && report.totals["queue"]?.wallSeconds == 10)
    precondition(report.overallRTF == 20.0 / 3600 && report.reusedChunks == 3)
    let revision = report.revision
    session.count(.inputLost)
    precondition(session.snapshot.revision == revision)

    let partial = AudioDiagnosticSession(kind: .recordedTranscription, audioSeconds: 3600,
      now: { clock.value }) { _ in }
    let finished = partial.begin(.recognition, audioSeconds: 60)
    clock.set(26)
    partial.end(finished, outcome: .empty)
    _ = partial.begin(.recognition, audioSeconds: 900)
    clock.set(56)
    partial.finish(.interrupted)
    precondition(partial.snapshot.overallRTF == nil)
    precondition(partial.snapshot.totals["recognition"]?.calls == 2)
    precondition(partial.snapshot.totals["recognition"]?.successfulCalls == 1)
    precondition(partial.snapshot.totals["recognition"]?.rtf == 0.1)

    let bounded = AudioDiagnosticSession(kind: .recording, now: { clock.value }) { _ in }
    for index in 0..<1000 {
      let span = bounded.begin(.quality, audioSeconds: 1)
      bounded.end(span, outcome: .success)
      bounded.sample(.init(footprintBytes: UInt64(index + 1000), batteryFraction: index == 0 ? 0.9 : 0.7,
        charging: false, lowPower: false, thermalState: index == 5 ? 3 : 0))
    }
    bounded.latency("recordingTap", .init(samples: 10, p50Microseconds: 100,
      p95Microseconds: 200, p99Microseconds: 300, maximumMicroseconds: 400))
    bounded.finish(.success)
    let retained = bounded.snapshot
    precondition(retained.isValid && retained.events.count == 256 && retained.omittedEvents == 1744)
    precondition(retained.samples.count == 256 && retained.omittedSamples == 744)
    precondition(retained.totals["quality"]?.calls == 1000)
    precondition(retained.firstBatteryFraction == 0.9 && retained.lastBatteryFraction == 0.7)
    precondition(retained.maximumThermalState == 3 && retained.sampledPeakFootprintBytes == 1999)
    precondition(retained.latencies?["recordingTap"]?.p95Microseconds == 200 && retained.isValid)

    let directory = root.appendingPathComponent("archive")
    let archive = AudioDiagnosticArchive(directory: directory)
    let epoch = AudioProcessingDiagnostics.generation
    await archive.update(report, generation: epoch)
    var older = report
    older.revision = 0
    older.reusedChunks = 0
    await archive.update(older, generation: epoch)
    let ordered = await archive.snapshot()
    precondition(ordered.first?.reusedChunks == 3)
    await archive.flush(generation: epoch)
    let reopened = AudioDiagnosticArchive(directory: directory)
    let restored = await reopened.snapshot()
    precondition(restored.first?.outcome == .success && restored.first?.totals["recognition"]?.rtf == 0.1)
    let inFlight = AudioDiagnosticSession(kind: .sourceExtraction, now: { clock.value }) { _ in }
    _ = inFlight.begin(.recognition, audioSeconds: 900)
    await archive.update(inFlight.snapshot, generation: epoch)
    await archive.flush(generation: epoch)
    let interrupted = await AudioDiagnosticArchive(directory: directory).snapshot()
    precondition(interrupted.first?.outcome == .interrupted)

    // Switching collection off/on must not let an old coalesced save discard
    // the replacement generation's finished report.
    let switching = AudioDiagnosticArchive(directory: root.appendingPathComponent("switching"))
    await switching.update(report, generation: epoch)
    AudioProcessingDiagnostics.invalidateSessions()
    let replacementEpoch = AudioProcessingDiagnostics.generation
    var replacement = report
    replacement.id = UUID()
    await switching.update(replacement, generation: replacementEpoch)
    await switching.flush(generation: epoch)
    await switching.flush(generation: replacementEpoch)
    let persistedReplacement = await AudioDiagnosticArchive(directory: root.appendingPathComponent("switching")).snapshot()
    precondition(persistedReplacement.contains(where: { $0.id == replacement.id }))

    AudioProcessingDiagnostics.invalidateSessions()
    await archive.clear()
    await archive.update(report, generation: epoch)
    let cleared = await archive.snapshot()
    precondition(cleared.isEmpty)
    let current = AudioProcessingDiagnostics.generation
    for _ in 0..<30 {
      var item = report
      item.id = UUID()
      await archive.update(item, generation: current)
    }
    let capped = await archive.snapshot()
    precondition(capped.count == 12)
    let exported = await archive.export()
    precondition(exported.utf8.count < AudioDiagnosticArchive.maximumBytes)
    let roundTrip = try JSONDecoder().decode([AudioDiagnosticReport].self, from: Data(exported.utf8))
    precondition(roundTrip.allSatisfy(\.isValid))

    let previous = UserDefaults.standard.object(forKey: AudioProcessingDiagnostics.enabledKey)
    defer {
      if let previous { UserDefaults.standard.set(previous, forKey: AudioProcessingDiagnostics.enabledKey) }
      else { UserDefaults.standard.removeObject(forKey: AudioProcessingDiagnostics.enabledKey) }
    }
    UserDefaults.standard.set(false, forKey: AudioProcessingDiagnostics.enabledKey)
    precondition(AudioProcessingDiagnostics.begin(.recording) == nil)
    UserDefaults.standard.set(true, forKey: AudioProcessingDiagnostics.enabledKey)
    do {
      _ = try await AudioProcessingDiagnostics.trace(.quality) { () async throws -> Bool in
        throw NSError(domain: "PRIVATE_AUDIO_CONTENT", code: 7,
          userInfo: [NSLocalizedDescriptionKey: "/private/person/secret-recording.m4a token=PRIVATE_CREDENTIAL"])
      } outcome: { _ in .success }
      preconditionFailure("Failure swallowed")
    } catch { }
    for _ in 0..<200 {
      if await AudioDiagnosticArchive.shared.snapshot().contains(where: { $0.outcome == .failed }) { break }
      await Task.yield()
    }
    let safe = await AudioDiagnosticArchive.shared.export()
    precondition(safe.contains("failed") && !safe.contains("PRIVATE_") && !safe.contains("secret-recording"))
    try Data(exported.utf8).write(to: root.appendingPathComponent("example-metrics.json"))
    print("AudioDiagnosticChecks: PASS. Monotonic RTF, partial-stage exclusion, queue separation, reuse, bounded samples/events, aggregate retention, closed-run refusal, real cache round-trip, interrupted run, collection-generation replacement, clear-generation and reordered-update refusal, disabled collection, and error-content redaction. Battery/device metrics are fixtures.")
  }
}

private final class MetricClock: Sendable {
  private let storage = Mutex(0.0)
  var value: Double { storage.withLock { $0 } }
  func set(_ seconds: Double) { storage.withLock { $0 = seconds } }
}
