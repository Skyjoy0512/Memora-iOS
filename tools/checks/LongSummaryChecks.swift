import Foundation
import Synchronization
import FoundationModels

@main
enum LongSummaryChecks {
  @MainActor static func main() async throws {
    for seconds in [30, 60, 120, 180] {
      for firstToken in [0, min(60, seconds)] {
        let clock = Timeline()
        let frames = [
          (0, ": waiting\n\n"),
          (firstToken, "data: {\"choices\":[{\"delta\":{\"content\":\"前半\"}}]}\n\n"),
          (seconds, "data: {\"choices\":[{\"delta\":{\"content\":\"後半\"},\"finish_reason\":\"stop\"}]}\n\n"),
          (seconds, "data: [DONE]\n\n")
        ]
        var publications: [String] = []
        let response = try await CloudTurnStreamReader.response(from: TimedBytes(frames: frames, clock: clock),
          provider: .chatCompletions, responseKind: .textCompletion, now: { clock.now },
          onText: { publications.append($0) })
        let result = try CloudSummaryResponse(response, provider: .chatCompletions)
        precondition(result.text == "前半後半" && !result.wasCutOff && publications.last == "前半後半")
        precondition(clock.elapsed == seconds)
        print("Virtual summary duration=\(seconds)s firstToken=\(firstToken)s: PASS")
      }
    }
    let clock = Timeline()
    let truncated = TimedBytes(frames: [(60, "data: {\"choices\":[{\"delta\":{\"content\":\"未完成\"}}]}\n\n")], clock: clock)
    do {
      _ = try await CloudTurnStreamReader.response(from: truncated, provider: .chatCompletions,
        responseKind: .textCompletion, onText: { _ in })
      preconditionFailure("Incomplete text committed")
    } catch AIAnswerFailure.connectionLost {}

    let diagnostic = SummaryDiagnostics(jobID: UUID(), engine: "cloud", provider: "openAI",
      model: "private-model-identifier", characters: 123, segments: 3)
    SummaryDiagnostics.$current.withValue(diagnostic) {
      diagnostic.record(.request)
      diagnostic.outputReceived()
      diagnostic.responseCompleted()
      diagnostic.failed(.providerTimedOut)
    }
    precondition(!diagnostic.report.contains("private-model-identifier"))
    precondition(diagnostic.events.map(\.stage) == [.started, .request, .firstToken, .lastToken, .responseComplete, .failed])
    precondition(diagnostic.report.contains("providerTimedOut"))
    let longDiagnostic = SummaryDiagnostics(jobID: UUID(), engine: "cloud", provider: "deepSeek",
      model: "private-model-identifier", characters: 123_456, segments: 999)
    for section in 0..<600 { longDiagnostic.record(.generation, code: section) }
    longDiagnostic.record(.request)
    longDiagnostic.outputReceived()
    longDiagnostic.responseCompleted()
    longDiagnostic.record(.saveStarted)
    longDiagnostic.record(.saveFailed)
    longDiagnostic.failed(.generationFailed)
    precondition(longDiagnostic.events.count == 256 && longDiagnostic.events.first?.stage == .started)
    precondition(longDiagnostic.events.last?.stage == .failed && longDiagnostic.events.last?.failure == "generationFailed")
    precondition(longDiagnostic.events.suffix(7).map(\.stage) == [.request, .firstToken, .lastToken, .responseComplete, .saveStarted, .saveFailed, .failed])
    precondition(longDiagnostic.report.contains("retainedEvents=256 omittedEvents=352"))
    precondition(!longDiagnostic.report.contains("private-model-identifier"))
    let correlated = SummaryDiagnostics(jobID: UUID(), engine: "cloud", provider: "fixture", model: "fixture", characters: 1, segments: 1)
    let firstRequest = UUID(), secondRequest = UUID()
    SummaryDiagnostics.$requestID.withValue(firstRequest) { correlated.outputReceived() }
    SummaryDiagnostics.$requestID.withValue(secondRequest) { correlated.outputReceived() }
    SummaryDiagnostics.$requestID.withValue(firstRequest) { correlated.responseCompleted() }
    precondition(correlated.events.contains { $0.stage == .lastToken && $0.requestID == secondRequest })
    SummaryDiagnostics.$requestID.withValue(secondRequest) { correlated.responseCompleted() }
    for id in [firstRequest, secondRequest] {
      precondition(correlated.events.filter { $0.stage == .firstToken && $0.requestID == id }.count == 1)
      precondition(correlated.events.filter { $0.stage == .lastToken && $0.requestID == id }.count == 1)
    }
    correlated.receivedUsage(["usage": ["prompt_tokens": 123, "completion_tokens": 45,
      "completion_tokens_details": ["reasoning_tokens": 30]]], usesAnthropicAPI: false)
    precondition(correlated.events.suffix(3).map(\.code) == [123, 45, 30])
    let beforeInvalid = correlated.events.count
    correlated.receivedUsage(["usage": ["prompt_tokens": true, "completion_tokens": -1,
      "completion_tokens_details": ["reasoning_tokens": "private"]]], usesAnthropicAPI: false)
    precondition(correlated.events.count == beforeInvalid)
    correlated.providerStopped("stop")
    correlated.providerStopped("private-provider-message")
    precondition(correlated.events.suffix(2).map(\.reason) == ["stop", "unrecognized"])
    precondition(!correlated.report.contains("private-provider-message"))
    SummaryDiagnostics.recordLifecycle(jobIDs: [correlated.jobID], isForeground: false)
    SummaryDiagnostics.recordLifecycle(jobIDs: [correlated.jobID], isForeground: true)
    precondition(correlated.events.suffix(2).map(\.stage) == [.enteredBackground, .enteredForeground])
    precondition(FoundationModelFailure.reason(for: NSError(domain: "fixture", code: 1)) == .generationFailed)
    precondition(FoundationModelFailure.reason(for: CancellationError()) == .cancelled)
    if #available(macOS 27.0, iOS 27.0, *) {
      precondition(FoundationModelFailure.reason(for: LanguageModelError.timeout(.init(debugDescription: "private"))) == .onDeviceTimedOut)
      precondition(FoundationModelFailure.reason(for: SystemLanguageModel.Error.assetsUnavailable(.init(debugDescription: "private"))) == .assetsUnavailable)
    }
    print("LongSummaryChecks: PASS; virtual receive times, EOF rejection, redacted/bounded timeline retaining late failures, and actual FoundationModels error types. No inference or network; OS/HTTP wall-clock deadlines are not simulated by the virtual clock.")
  }

  final class Timeline: Sendable {
    let start = ContinuousClock.now
    private let state = Mutex(0)
    var elapsed: Int {
      get { state.withLock { $0 } }
      set { state.withLock { $0 = newValue } }
    }
    var now: ContinuousClock.Instant { start.advanced(by: .seconds(elapsed)) }
  }
  struct TimedBytes: AsyncSequence, Sendable {
    var frames: [(Int, String)]
    var clock: Timeline
    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(frames: frames.map { ($0.0, Array($0.1.utf8)) }, clock: clock) }
    struct AsyncIterator: AsyncIteratorProtocol {
      var frames: [(Int, [UInt8])]
      var clock: Timeline
      var frame = 0
      var offset = 0
      mutating func next() async throws -> UInt8? {
        try Task.checkCancellation()
        guard frame < frames.count else { return nil }
        if offset == 0 { clock.elapsed = frames[frame].0; await Task.yield() }
        let byte = frames[frame].1[offset]
        offset += 1
        if offset == frames[frame].1.count { frame += 1; offset = 0 }
        return byte
      }
    }
  }
}
