import AVFAudio
import Foundation
import Observation
import Speech

/// Shows a live transcription while recording, on iOS 26 and only from the
/// on-device `SpeechAnalyzer`. It is display-only: the result saved with the
/// record is made afterwards from the stored audio, so a live miss cannot change
/// what is kept. When no engine can run, it says why and shows nothing.
@MainActor
@Observable
final class RealtimeTranscriptionService {
  /// Lines that have settled, oldest first.
  private(set) var history = LiveTranscriptHistory()
  /// The line still being recognised, shown lighter.
  private(set) var volatileText = ""
  private(set) var isRunning = false
  /// Why live transcription is not showing, if it cannot run here.
  private(set) var unavailableReason: String?

  @ObservationIgnored private var session: Any?
  @ObservationIgnored private var stoppingTask: Task<Void, Never>?
  @ObservationIgnored private var stoppingGeneration = UUID()

  static let enabledKey = "memora.liveTranscription"

  static var isEnabled: Bool {
    UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
  }

  func start() {
    guard session == nil else { return }
    volatileText = ""
    unavailableReason = nil

    guard Self.isEnabled else {
      unavailableReason = "設定で録音中の文字起こしをオフにしています。"
      return
    }
    guard #available(iOS 26.0, *) else {
      unavailableReason = "録音中の文字起こしは iOS 26 以降で使えます。"
      return
    }
    guard SpeechTranscriber.isAvailable else {
      unavailableReason = "この端末では録音中の文字起こしを使えません。"
      return
    }

    let session = RealtimeTranscriptionSession(
      locale: (RecognitionLanguage(rawValue: UserDefaults.standard.string(forKey: "memora.transcriptionLanguage") ?? "") ?? .japanese).locale,
      onFinal: { [weak self] text in
        self?.history.append(text)
        self?.volatileText = ""
      },
      onVolatile: { [weak self] text in
        let bounded = LiveTranscriptHistory.boundedText(text)
        if self?.volatileText != bounded { self?.volatileText = bounded }
      },
      onRunning: { [weak self] running in
        self?.isRunning = running
      },
      onUnavailable: { [weak self] reason in
        self?.unavailableReason = reason
      }
    )
    self.session = session
    session.start(after: stoppingTask)
  }

  func stop() {
    if #available(iOS 26.0, *) {
      if let previous = (session as? RealtimeTranscriptionSession)?.stop() {
        stoppingGeneration = UUID()
        stoppingTask = previous
      }
    }
    session = nil
    isRunning = false
  }

  func waitUntilStopped() async {
    let generation = stoppingGeneration
    await stoppingTask?.value
    if stoppingGeneration == generation { stoppingTask = nil }
  }

  func suspendForPowerSaving() {
    stop()
    unavailableReason = "省電力動作中です。音声は同じ品質で録音し、保存後に文字起こしします。"
  }

  func resetHistory() {
    history = LiveTranscriptHistory()
    volatileText = ""
  }
}

/// The iOS 26 live session: an input tap feeds the on-device analyzer and its
/// volatile results are handed back to the service.
@available(iOS 26.0, *)
@MainActor
private final class RealtimeTranscriptionSession {
  private let locale: Locale
  private let onFinal: (String) -> Void
  private let onVolatile: (String) -> Void
  private let onRunning: (Bool) -> Void
  private let onUnavailable: (String) -> Void

  private var engine: AVAudioEngine?
  private var task: Task<Void, Never>?
  private var continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation?
  private var hasInstalledInputTap = false
  private var isStopped = false
  private var analyzer: SpeechAnalyzer?

  init(
    locale: Locale,
    onFinal: @escaping (String) -> Void,
    onVolatile: @escaping (String) -> Void,
    onRunning: @escaping (Bool) -> Void,
    onUnavailable: @escaping (String) -> Void
  ) {
    self.locale = locale
    self.onFinal = onFinal
    self.onVolatile = onVolatile
    self.onRunning = onRunning
    self.onUnavailable = onUnavailable
  }

  func start(after previous: Task<Void, Never>?) {
    task = Task { [weak self] in
      await previous?.value
      guard !Task.isCancelled else { return }
      await self?.run()
    }
  }

  @discardableResult
  func stop() -> Task<Void, Never>? {
    isStopped = true
    let previous = task
    task?.cancel()
    task = nil
    stopEngine()
    let analyzer = self.analyzer
    self.analyzer = nil
    Task { await analyzer?.cancelAndFinishNow() }
    onRunning(false)
    return previous
  }

  private func stopEngine() {
    continuation?.finish()
    continuation = nil
    if hasInstalledInputTap {
      engine?.inputNode.removeTap(onBus: 0)
      hasInstalledInputTap = false
    }
    engine?.stop()
    engine = nil
  }

  private func run() async {
    guard !Task.isCancelled, !isStopped else { return }
    let diagnostic = AudioProcessingDiagnostics.begin(.liveTranscription)
    diagnostic?.setEngine(.appleSpeech)
    let modelPreparation = diagnostic?.begin(.modelPreparation)
    var diagnosticOutcome: AudioDiagnosticReport.Outcome = .unavailable
    defer { diagnostic?.finish(Task.isCancelled ? .cancelled : diagnosticOutcome) }
    let preparation = AudioProcessingDiagnostics.signposter.beginInterval("LiveModelPreparation")
    var prepared = false
    defer {
      if !prepared { AudioProcessingDiagnostics.signposter.endInterval("LiveModelPreparation", preparation) }
    }
    guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
      if !isStopped { onUnavailable("この言語は録音中の文字起こしに対応していません。") }
      return
    }
    guard !Task.isCancelled, !isStopped else { return }

    let transcriber = SpeechTranscriber(
      locale: supported,
      transcriptionOptions: [.etiquetteReplacements],
      // Live recognition does want volatile progress, so a phrase appears as it
      // is spoken and settles into place.
      reportingOptions: [.volatileResults],
      attributeOptions: [.audioTimeRange]
    )

    do {
      if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
        try await request.downloadAndInstall()
      }
    } catch {
      guard !isStopped else { return }
      diagnosticOutcome = .failed
      onUnavailable("文字起こしモデルを準備できませんでした。")
      return
    }
    if Task.isCancelled { return }

    guard AVAudioSession.sharedInstance().isInputAvailable else {
      onUnavailable("マイクの入力がありません。録音後の文字起こしをお使いください。")
      return
    }
    let engine = AVAudioEngine()
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    let hardwareFormat = input.inputFormat(forBus: 0)
    guard format.sampleRate.isFinite, format.sampleRate > 0, format.channelCount > 0,
          hardwareFormat.sampleRate.isFinite, hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0,
          format.sampleRate == hardwareFormat.sampleRate else {
      onUnavailable("マイクの形式を確認できませんでした。録音後の文字起こしをお使いください。")
      return
    }
    guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: format) else {
      if !isStopped { onUnavailable("録音中の文字起こしに対応する音声形式がありません。") }
      return
    }
    guard !Task.isCancelled, !isStopped else { return }
    guard input.outputFormat(forBus: 0) == format,
          let converter = LiveAudioBufferConverter(source: format, target: analyzerFormat) else {
      onUnavailable("マイクの形式が変わりました。録音後の文字起こしをお使いください。")
      return
    }
    let (stream, continuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream(bufferingPolicy: .bufferingNewest(16))
    self.continuation = continuation
    input.installTap(onBus: 0, bufferSize: 4_096, format: nil) { @Sendable buffer, _ in
      do {
        guard let ownedBuffer = try converter.convert(buffer) else { return }
        if case .dropped = continuation.yield(AnalyzerInput(buffer: ownedBuffer)) {
          diagnostic?.count(.liveBufferDropped)
          continuation.finish(throwing: CocoaError(.coderInvalidValue))
        }
      } catch {
        continuation.finish(throwing: error)
      }
    }
    hasInstalledInputTap = true
    self.engine = engine

    let analyzer = SpeechAnalyzer(modules: [transcriber])
    self.analyzer = analyzer
    AudioProcessingDiagnostics.signposter.endInterval("LiveModelPreparation", preparation)
    diagnostic?.end(modelPreparation, outcome: .success)
    _ = diagnostic?.begin(.recognition)
    prepared = true
    let recognition = AudioProcessingDiagnostics.signposter.beginInterval("LiveRecognition")
    defer { AudioProcessingDiagnostics.signposter.endInterval("LiveRecognition", recognition) }

    let collect = Task { [weak self] in
      do {
        for try await result in transcriber.results {
          guard let self, !self.isStopped else { return }
          let text = String(result.text.characters)
          guard !text.isEmpty else { continue }
          await MainActor.run {
            guard !self.isStopped else { return }
            if result.isFinal {
              self.onFinal(text)
            } else {
              self.onVolatile(text)
            }
          }
        }
      } catch {
        guard let self, !self.isStopped, !Task.isCancelled else { return }
        self.onUnavailable("ライブ認識を停止しました。音声は録音を続け、保存後に文字起こしします。")
        self.stop()
      }
    }

    do {
      engine.prepare()
      try engine.start()
      onRunning(true)
      diagnosticOutcome = .success
      _ = try await analyzer.analyzeSequence(stream)
      try await analyzer.finalizeAndFinishThroughEndOfInput()
    } catch {
      if !Task.isCancelled { diagnosticOutcome = .failed }
      if !Task.isCancelled {
        onUnavailable("録音中の文字起こしを停止しました。音声の録音は続けています。保存後に文字起こしできます。")
      }
    }

    collect.cancel()
    stopEngine()
    // Finishing the stream alone does not guarantee the model has stopped.
    await analyzer.cancelAndFinishNow()
    self.analyzer = nil
    _ = await collect.result
    if !isStopped { onRunning(false) }
  }
}
