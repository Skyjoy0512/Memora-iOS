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
  private(set) var finalized: [String] = []
  /// The line still being recognised, shown lighter.
  private(set) var volatileText = ""
  private(set) var isRunning = false
  /// Why live transcription is not showing, if it cannot run here.
  private(set) var unavailableReason: String?

  @ObservationIgnored private var session: Any?

  static let enabledKey = "memora.liveTranscription"

  static var isEnabled: Bool {
    UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
  }

  func start() {
    guard session == nil else { return }
    finalized = []
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
      onFinal: { [weak self] text in
        self?.finalized.append(text)
        self?.volatileText = ""
      },
      onVolatile: { [weak self] text in
        self?.volatileText = text
      },
      onRunning: { [weak self] running in
        self?.isRunning = running
      },
      onUnavailable: { [weak self] reason in
        self?.unavailableReason = reason
      }
    )
    self.session = session
    session.start()
  }

  func stop() {
    if #available(iOS 26.0, *) {
      (session as? RealtimeTranscriptionSession)?.stop()
    }
    session = nil
    isRunning = false
  }
}

/// The iOS 26 live session: an input tap feeds the on-device analyzer and its
/// volatile results are handed back to the service.
@available(iOS 26.0, *)
@MainActor
private final class RealtimeTranscriptionSession {
  private let onFinal: (String) -> Void
  private let onVolatile: (String) -> Void
  private let onRunning: (Bool) -> Void
  private let onUnavailable: (String) -> Void

  private var engine: AVAudioEngine?
  private var task: Task<Void, Never>?
  private var continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation?
  private var hasInstalledInputTap = false
  private var isStopped = false

  init(
    onFinal: @escaping (String) -> Void,
    onVolatile: @escaping (String) -> Void,
    onRunning: @escaping (Bool) -> Void,
    onUnavailable: @escaping (String) -> Void
  ) {
    self.onFinal = onFinal
    self.onVolatile = onVolatile
    self.onRunning = onRunning
    self.onUnavailable = onUnavailable
  }

  func start() {
    task = Task { [weak self] in await self?.run() }
  }

  func stop() {
    isStopped = true
    task?.cancel()
    task = nil
    stopEngine()
    onRunning(false)
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
    guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else {
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
      onUnavailable("文字起こしモデルを準備できませんでした。")
      return
    }
    if Task.isCancelled { return }

    let analyzer = SpeechAnalyzer(modules: [transcriber])

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
          continuation.finish(throwing: CocoaError(.coderInvalidValue))
        }
      } catch {
        continuation.finish(throwing: error)
      }
    }
    hasInstalledInputTap = true
    self.engine = engine

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
        // A stopped or failed run simply stops updating.
      }
    }

    do {
      engine.prepare()
      try engine.start()
      onRunning(true)
      _ = try await analyzer.analyzeSequence(stream)
      try await analyzer.finalizeAndFinishThroughEndOfInput()
    } catch {
      if !Task.isCancelled {
        onUnavailable("録音中の文字起こしを停止しました。音声の録音は続けています。保存後に文字起こしできます。")
      }
    }

    collect.cancel()
    stopEngine()
    if !isStopped { onRunning(false) }
  }
}
