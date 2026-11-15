import AVFAudio
import Foundation
import Speech

/// Explicitly installs and warms the Japanese on-device model before listening.
/// Each utterance owns a fresh analyzer; old results cannot enter the next turn.
@available(iOS 26.0, *)
@MainActor
final class LiveVoiceRecognizer {
  private var locale: Locale?
  private var task: Task<Void, Never>?
  private var generation = UUID()

  func prepare(onDownload: () -> Void) async throws {
    guard let supported = await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: "ja-JP")) else {
      throw LiveVoiceError.unavailable("この端末では日本語のオンデバイス音声認識を利用できません。")
    }
    try Task.checkCancellation()
    let transcriber = Self.transcriber(locale: supported)
    if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
      try Task.checkCancellation()
      onDownload()
      try await request.downloadAndInstall()
    }
    try Task.checkCancellation()
    locale = supported
  }

  func start(format: AVAudioFormat, bridge: LiveMicrophoneBridge,
             onReady: @escaping () -> Void,
             onText: @escaping (String) -> Void,
             onFailure: @escaping (Error) -> Void) {
    let previous = task
    previous?.cancel()
    let current = UUID()
    generation = current
    bridge.replace(with: nil)
    task = Task { [weak self] in
      await previous?.value
      guard let self, self.generation == current, !Task.isCancelled, let locale = self.locale else { return }
      let transcriber = Self.transcriber(locale: locale)
      let analyzer = SpeechAnalyzer(modules: [transcriber])
      await withTaskCancellationHandler {
        var collector: Task<Void, Never>?
        do {
          guard let target = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: format) else {
            throw LiveVoiceError.unavailable("マイクの音声形式を日本語の音声認識に変換できません。")
          }
          try await analyzer.prepareToAnalyze(in: target)
          try Task.checkCancellation()
          guard self.generation == current else { await analyzer.cancelAndFinishNow(); return }
          let (stream, continuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream(bufferingPolicy: .bufferingOldest(16))
          guard let feeder = LiveAudioInputFeeder(source: format, target: target, continuation: continuation, diagnostic: nil) else {
            throw LiveVoiceError.unavailable("マイクの音声形式を変換できません。")
          }
          bridge.replace(with: feeder)
          collector = Task { [weak self] in
            var settled = ""
            do {
              for try await result in transcriber.results {
                guard let self, self.generation == current, !Task.isCancelled else { return }
                let text = String(result.text.characters)
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                // Analyzer finals are phrases, not the end of a conversation turn.
                onText(settled + text)
                if result.isFinal { settled += text }
              }
            } catch {
              guard let self, self.generation == current, !Task.isCancelled else { return }
              onFailure(error)
            }
          }
          print("[Live] recognizer ready: Japanese on-device, inputRate=\(Int(format.sampleRate))")
          onReady()
          _ = try await analyzer.analyzeSequence(stream)
          try Task.checkCancellation()
          if self.generation == current {
            onFailure(LiveVoiceError.unavailable("音声認識が終了しました。Liveを再開してください。"))
          }
        } catch {
          if self.generation == current, !Task.isCancelled { onFailure(error) }
        }
        collector?.cancel()
        if self.generation == current { bridge.replace(with: nil) }
        await analyzer.cancelAndFinishNow()
        await collector?.value
      } onCancel: {
        Task { await analyzer.cancelAndFinishNow() }
      }
    }
  }

  func stop(bridge: LiveMicrophoneBridge) {
    generation = UUID()
    bridge.replace(with: nil)
    task?.cancel()
  }

  private static func transcriber(locale: Locale) -> DictationTranscriber {
    DictationTranscriber(locale: locale, contentHints: [.farField],
      transcriptionOptions: [.punctuation], reportingOptions: [.volatileResults], attributeOptions: [])
  }
}
