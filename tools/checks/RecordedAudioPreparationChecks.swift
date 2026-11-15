import AVFoundation
import Foundation
import Synchronization

enum RecordedAudioPreparationChecks {
  static func run(root: URL, source: URL) async throws {
    try policyBoundaries(root)
    let stages = root.appendingPathComponent("lookahead-stages")
    let staging = SourceMediaStaging(directory: stages, availableCapacity: { _ in 10 * 1_024 * 1_024 * 1_024 })
    let sequential = try await completed(root: root, source: source, staging: staging, name: "sequential",
      policy: .validated, expectsOverlap: false)
    let candidate = try await completed(root: root, source: source, staging: staging, name: "candidate",
      policy: candidatePolicy, expectsOverlap: true)
    precondition(sequential == candidate, "Preparation changed settled transcript content or timestamps")
    let fallback = try await completed(root: root, source: source, staging: staging, name: "resource-fallback",
      policy: .candidate { _ in throw SourceMediaFailure.capacity }, expectsOverlap: false)
    precondition(fallback == sequential, "Optional resource probing prevented sequential preparation")
    try await cancellation(root: root, source: source, staging: staging)
    try await thermalResume(root: root, source: source, staging: staging, expected: sequential)
    try await failedSuffix(root: root, source: source, staging: staging, expected: sequential)
    try await changedOriginal(root: root, source: source, staging: staging)
    let remaining = try FileManager.default.contentsOfDirectory(atPath: stages.path)
    precondition(remaining.isEmpty)
    precondition(FileManager.default.fileExists(atPath: source.path))
    print("RecordedAudioPreparationChecks: PASS. Real WAV/AAC exports overlap one next chunk with fixture recognition; default sequential and optional-probe fallback match; 100MiB resource headroom boundaries; cancellation drains children and deletes stages; thermal revalidation retains only settled prefix; failed suffix resumes without re-recognizing prefix. No actual recognizer/model, iPhone speed, energy or memory claim; production overlap gate stays closed.")
  }

  private static var candidatePolicy: RecordedAudioPreparationPolicy {
    .candidate { directory in
      var resources = try RecordedAudioPreparationPolicy.Resources.read(directory)
      // The host's unrelated power/thermal state cannot make a concurrency
      // regression silently exercise only the sequential fallback.
      resources.lowPower = false
      resources.thermal = .nominal
      precondition(resources.permitsLookahead, "Host lacks the candidate's real disk headroom")
      return resources
    }
  }

  private static func policyBoundaries(_ root: URL) throws {
    let maximum = SourceMediaAudioExport.maximumOutputBytes
    var resources = RecordedAudioPreparationPolicy.Resources(
      stageBytes: SourceMediaStaging.maximumStageBytes - maximum,
      totalBytes: SourceMediaStaging.maximumTotalBytes - maximum,
      availableBytes: SourceMediaStaging.minimumAvailableBytes + maximum,
      lowPower: false, thermal: .nominal)
    precondition(resources.permitsLookahead)
    resources.stageBytes += 1
    precondition(!resources.permitsLookahead)
    resources.stageBytes -= 1
    resources.totalBytes += 1
    precondition(!resources.permitsLookahead)
    resources.totalBytes -= 1
    resources.availableBytes -= 1
    precondition(!resources.permitsLookahead)
    resources.availableBytes += 1
    resources.lowPower = true
    precondition(!resources.permitsLookahead)
    resources.lowPower = false
    for thermal in [ProcessInfo.ThermalState.fair, .serious, .critical] {
      resources.thermal = thermal
      precondition(!resources.permitsLookahead)
    }
    resources.thermal = .nominal
    resources.stageBytes = -1
    precondition(!resources.permitsLookahead)
    resources.stageBytes = 1
    resources.totalBytes = 0
    precondition(!resources.permitsLookahead)
    resources.stageBytes = .max
    resources.totalBytes = .max
    resources.availableBytes = .max
    precondition(!resources.permitsLookahead)
    precondition(!RecordedAudioPreparationPolicy.validated.shouldPrepareNext(in: root))
    let temporary = root.appendingPathComponent("lease-fixture.m4a")
    try Data([1]).write(to: temporary)
    var lease: SourceMediaAudioLease? = SourceMediaAudioLease(url: temporary)
    lease?.remove()
    lease?.remove()
    lease = nil
    precondition(!FileManager.default.fileExists(atPath: temporary.path))
  }

  private static func completed(root: URL, source: URL, staging: SourceMediaStaging, name: String,
                                policy: RecordedAudioPreparationPolicy, expectsOverlap: Bool) async throws -> [TranscriptSegment] {
    let diagnostic = AudioDiagnosticSession(kind: .recordedTranscription) { _ in }
    let calls = Mutex(0)
    let outcome = await AudioProcessingDiagnostics.$current.withValue(diagnostic) {
      await RecordedAudioTranscription.transcribe(source, locale: Locale(identifier: "ja-JP"), vocabulary: [],
        checkpointStore: SourceMediaCheckpointStore(directory: root.appendingPathComponent(name)),
        staging: staging, preparationPolicy: policy,
        checkReadiness: { try AudioProcessingReadiness.check(thermalState: .nominal) }) { audio in
        let call = calls.withLock { $0 += 1; return $0 }
        if call == 1 {
          if expectsOverlap {
            await waitForExports(2, diagnostic: diagnostic)
            let next = audio.deletingLastPathComponent().appendingPathComponent("chunk-1.m4a")
            guard let duration = try? await AVURLAsset(url: next).load(.duration).seconds else {
              preconditionFailure("Lookahead was not a complete AAC file while recognition held its predecessor")
            }
            precondition(abs(duration - 1) < 0.05)
            precondition(FileManager.default.fileExists(atPath: audio.path), "Lookahead replaced recognition input")
          } else {
            precondition(exports(diagnostic) == 1, "Sequential preparation speculated")
          }
        }
        return fixtureSegments(audio)
      }
    }
    guard case .segments(let segments) = outcome else { preconditionFailure("Preparation did not complete: \(outcome)") }
    precondition(calls.withLock { $0 } == 2 && exports(diagnostic) == 2 && diagnostic.snapshot.completedChunks == 2)
    precondition(segments.map(\.timestamp) == [0.25, 900.25])
    precondition(segments.map(\.endTime) == [0.5, 900.5])
    return segments
  }

  private static func cancellation(root: URL, source: URL, staging: SourceMediaStaging) async throws {
    let diagnostic = AudioDiagnosticSession(kind: .recordedTranscription) { _ in }
    let entered = Mutex(false)
    let task = Task {
      await AudioProcessingDiagnostics.$current.withValue(diagnostic) {
        await RecordedAudioTranscription.transcribe(source, locale: Locale(identifier: "ja-JP"), vocabulary: [],
          checkpointStore: SourceMediaCheckpointStore(directory: root.appendingPathComponent("cancelled-lookahead")),
          staging: staging, preparationPolicy: candidatePolicy,
          checkReadiness: { try AudioProcessingReadiness.check(thermalState: .nominal) }) { _ in
          await waitForExports(2, diagnostic: diagnostic)
          entered.withLock { $0 = true }
          do { try await Task.sleep(for: .seconds(30)) } catch { }
          return .cancelled
        }
      }
    }
    let deadline = ContinuousClock.now.advanced(by: .seconds(20))
    while !entered.withLock({ $0 }), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
    precondition(entered.withLock { $0 }, "Recognition did not reach the cancellation boundary")
    task.cancel()
    guard case .cancelled = await task.value else { preconditionFailure("Cancelled pipeline published a transcript") }
    precondition(diagnostic.snapshot.completedChunks == 0)
  }

  private static func thermalResume(root: URL, source: URL, staging: SourceMediaStaging,
                                     expected: [TranscriptSegment]) async throws {
    let diagnostic = AudioDiagnosticSession(kind: .recordedTranscription) { _ in }
    let heat = Mutex<ProcessInfo.ThermalState>(.nominal)
    let calls = Mutex(0)
    let directory = root.appendingPathComponent("lookahead-thermal-prefix")
    let outcome = await AudioProcessingDiagnostics.$current.withValue(diagnostic) {
      await RecordedAudioTranscription.transcribe(source, locale: Locale(identifier: "ja-JP"), vocabulary: [],
        checkpointStore: SourceMediaCheckpointStore(directory: directory), staging: staging,
        preparationPolicy: candidatePolicy,
        checkReadiness: { try AudioProcessingReadiness.check(thermalState: heat.withLock { $0 }) }) { audio in
        calls.withLock { $0 += 1 }
        await waitForExports(2, diagnostic: diagnostic)
        heat.withLock { $0 = .serious }
        return fixtureSegments(audio)
      }
    }
    guard case .failed = outcome else { preconditionFailure("Heated prepared suffix was published") }
    precondition(calls.withLock { $0 } == 1 && diagnostic.snapshot.completedChunks == 1)
    precondition(diagnostic.snapshot.outcome == .deferred)
    let resumedDiagnostic = AudioDiagnosticSession(kind: .recordedTranscription) { _ in }
    let resumed = await AudioProcessingDiagnostics.$current.withValue(resumedDiagnostic) {
      await RecordedAudioTranscription.transcribe(source, locale: Locale(identifier: "ja-JP"), vocabulary: [],
        checkpointStore: SourceMediaCheckpointStore(directory: directory), staging: staging,
        preparationPolicy: candidatePolicy,
        checkReadiness: { try AudioProcessingReadiness.check(thermalState: .nominal) }) { audio in
        calls.withLock { $0 += 1 }
        return fixtureSegments(audio)
      }
    }
    guard case .segments(let segments) = resumed else { preconditionFailure("Thermal suffix could not resume") }
    precondition(segments == expected && calls.withLock { $0 } == 2)
    precondition(resumedDiagnostic.snapshot.reusedChunks == 1 && exports(resumedDiagnostic) == 1)
  }

  private static func failedSuffix(root: URL, source: URL, staging: SourceMediaStaging,
                                    expected: [TranscriptSegment]) async throws {
    let directory = root.appendingPathComponent("lookahead-failed-prefix")
    let calls = Mutex(0)
    let recognize: @Sendable (URL) async -> TranscriptionOutcome = { audio in
      let call = calls.withLock { $0 += 1; return $0 }
      return call == 2 ? .failed("fixture suffix failure") : fixtureSegments(audio)
    }
    let failed = await RecordedAudioTranscription.transcribe(source, locale: Locale(identifier: "ja-JP"), vocabulary: [],
      checkpointStore: SourceMediaCheckpointStore(directory: directory), staging: staging,
      preparationPolicy: candidatePolicy,
      checkReadiness: { try AudioProcessingReadiness.check(thermalState: .nominal) }, recognize: recognize)
    guard case .failed = failed else { preconditionFailure("Incomplete candidate was published") }
    let resumed = await RecordedAudioTranscription.transcribe(source, locale: Locale(identifier: "ja-JP"), vocabulary: [],
      checkpointStore: SourceMediaCheckpointStore(directory: directory), staging: staging,
      preparationPolicy: candidatePolicy,
      checkReadiness: { try AudioProcessingReadiness.check(thermalState: .nominal) }, recognize: recognize)
    guard case .segments(let segments) = resumed else { preconditionFailure("Candidate suffix could not resume") }
    precondition(segments == expected && calls.withLock { $0 } == 3)
  }

  private static func exports(_ diagnostic: AudioDiagnosticSession) -> Int {
    diagnostic.snapshot.totals[AudioDiagnosticReport.Stage.exportAudio.rawValue]?.successfulCalls ?? 0
  }

  private static func changedOriginal(root: URL, source: URL, staging: SourceMediaStaging) async throws {
    let changed = root.appendingPathComponent("changed-lookahead-original.wav")
    try FileManager.default.copyItem(at: source, to: changed)
    let originalSize = try FileManager.default.attributesOfItem(atPath: changed.path)[.size] as! NSNumber
    let diagnostic = AudioDiagnosticSession(kind: .recordedTranscription) { _ in }
    let calls = Mutex(0)
    let outcome = await AudioProcessingDiagnostics.$current.withValue(diagnostic) {
      await RecordedAudioTranscription.transcribe(changed, locale: Locale(identifier: "ja-JP"), vocabulary: [],
        checkpointStore: SourceMediaCheckpointStore(directory: root.appendingPathComponent("changed-lookahead-prefix")),
        staging: staging, preparationPolicy: candidatePolicy,
        checkReadiness: { try AudioProcessingReadiness.check(thermalState: .nominal) }) { audio in
        let call = calls.withLock { $0 += 1; return $0 }
        if call == 1 {
          await waitForExports(2, diagnostic: diagnostic)
          do {
            let handle = try FileHandle(forWritingTo: changed)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data([1]))
          } catch { preconditionFailure("Fixture could not change its own original") }
        }
        return fixtureSegments(audio)
      }
    }
    guard case .failed = outcome else { preconditionFailure("Changed original published a completed transcript") }
    precondition(calls.withLock { $0 } == 2)
    let changedSize = try FileManager.default.attributesOfItem(atPath: changed.path)[.size] as! NSNumber
    precondition(changedSize.int64Value == originalSize.int64Value + 1, "Fixture change did not survive processing")
  }

  private static func waitForExports(_ expected: Int, diagnostic: AudioDiagnosticSession) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(20))
    while exports(diagnostic) < expected, ContinuousClock.now < deadline, !Task.isCancelled {
      do { try await Task.sleep(for: .milliseconds(20)) } catch { break }
    }
    precondition(exports(diagnostic) == expected, "Expected a completed export while fixture recognition was suspended")
  }

  private static func fixtureSegments(_ audio: URL) -> TranscriptionOutcome {
    let index = Int(audio.deletingPathExtension().lastPathComponent.split(separator: "-").last!)!
    let id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!
    return .segments([.init(id: id, speaker: "話者", speakerIsCertain: false,
      timestamp: 0.25, text: "fixture-only settled speech", endTime: 0.5)])
  }
}
