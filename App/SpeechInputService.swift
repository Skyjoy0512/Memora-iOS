import AVFAudio
import Foundation
import Observation
@preconcurrency import Speech

@MainActor
@Observable
final class SpeechInputService {
  private(set) var isListening = false
  private(set) var errorMessage: String?
  /// Smoothed 0...1 loudness for the voice glow.
  private(set) var audioLevel: Double = 0

  @ObservationIgnored private let audioEngine = AVAudioEngine()
  @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
  @ObservationIgnored private var hasInstalledInputTap = false
  /// Identifies one run, so callbacks and permission waits from a replaced run
  /// cannot touch the current one.
  @ObservationIgnored private var runID: UUID?
  /// True from the moment a start begins, so repeated taps during the permission
  /// prompts cannot begin two runs.
  @ObservationIgnored private var isStarting = false
  /// The session claim this run holds, so only this run gives it up.
  @ObservationIgnored private var sessionToken: AudioSessionCoordinator.Token?
  /// The coordinator's handle for this service's stop request, so the service
  /// removes only its own when it goes away.
  @ObservationIgnored private var stopperID: UUID?

  init() {
    // Registered once, so a recording can ask voice input to stop and wait for it
    // before taking the session. The handler holds this service weakly.
    stopperID = AudioSessionCoordinator.shared.registerStopper(.speechInput) { [weak self] in
      self?.stop()
    }
  }

  isolated deinit {
    guard let stopperID = self.stopperID else { return }
    AudioSessionCoordinator.shared.unregisterStopper(stopperID, for: .speechInput)
  }

  func toggle(transcriptChanged: @escaping @MainActor (String) -> Void) async {
    if isListening {
      stop()
    } else if !isStarting {
      await start(transcriptChanged: transcriptChanged)
    }
  }

  func stop() {
    runID = nil
    isStarting = false
    if audioEngine.isRunning {
      audioEngine.stop()
    }
    if hasInstalledInputTap {
      audioEngine.inputNode.removeTap(onBus: 0)
      hasInstalledInputTap = false
    }
    recognitionRequest?.endAudio()
    recognitionTask?.cancel()
    recognitionRequest = nil
    recognitionTask = nil
    isListening = false
    audioLevel = 0
    // Only the claim this run holds may switch it off. Stopping voice input
    // after a text question, or when a screen closes, must not silence a
    // recording that is running or a newer voice run.
    if let sessionToken {
      AudioSessionCoordinator.shared.release(sessionToken)
      self.sessionToken = nil
    }
  }

  func clearError() {
    errorMessage = nil
  }

  /// Explains why voice input is not available without touching the audio
  /// session — used while a recording owns it.
  func refuse(_ reason: String) {
    errorMessage = reason
  }

  private func start(transcriptChanged: @escaping @MainActor (String) -> Void) async {
    let run = UUID()
    runID = run
    isStarting = true
    defer { if runID == run { isStarting = false } }
    errorMessage = nil

    // Each await can outlast the screen that asked for voice input, so the run
    // is re-checked before touching any state.
    guard await requestSpeechPermission() else {
      errorMessage = "音声認識へのアクセスを設定で許可してください。"
      return
    }
    guard runID == run else { return }
    guard await requestMicrophonePermission() else {
      errorMessage = "マイクへのアクセスを設定で許可してください。"
      return
    }
    guard runID == run else { return }
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP")), recognizer.isAvailable else {
      errorMessage = "音声入力を利用できません。通信状態を確認してください。"
      return
    }
    guard runID == run else { return }

    // The permission prompts above can take a while, so the session is claimed
    // only now, and only if it is still free.
    guard let token = AudioSessionCoordinator.shared.claim(.speechInput) else {
      errorMessage = AudioSessionCoordinator.shared.refusal(for: .speechInput)
        ?? "今は音声入力できません。"
      return
    }
    sessionToken = token

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.record, mode: .measurement, options: .duckOthers)
      try session.setActive(true, options: .notifyOthersOnDeactivation)

      let request = SFSpeechAudioBufferRecognitionRequest()
      request.shouldReportPartialResults = true
      request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
      recognitionRequest = request

      let inputNode = audioEngine.inputNode
      let format = inputNode.outputFormat(forBus: 0)
      guard format.sampleRate > 0 else {
        throw SpeechInputError.noAudioInput
      }
      inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { @Sendable [weak self] buffer, _ in
        request.append(buffer)
        let level = Self.loudness(of: buffer)
        Task { @MainActor [weak self] in
          guard let self, self.runID == run else { return }
          self.apply(level: level)
        }
      }
      hasInstalledInputTap = true

      recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
        Task { @MainActor in
          // A callback from a run that has since ended is ignored.
          guard let self, self.runID == run else { return }
          if let result {
            transcriptChanged(result.bestTranscription.formattedString)
          }
          if result?.isFinal == true || error != nil {
            self.stop()
          }
        }
      }

      audioEngine.prepare()
      try audioEngine.start()
      isListening = true
    } catch {
      stop()
      errorMessage = error.localizedDescription
    }
  }

  /// Maps a buffer's RMS to 0...1 and eases toward it so the glow is lively
  /// without flickering.
  private func apply(level: Double) {
    let rate = level > audioLevel ? 0.6 : 0.12
    audioLevel += (level - audioLevel) * rate
  }

  private nonisolated static func loudness(of buffer: AVAudioPCMBuffer) -> Double {
    guard let samples = buffer.floatChannelData?[0] else { return 0 }
    let frames = Int(buffer.frameLength)
    guard frames > 0 else { return 0 }

    var sum: Float = 0
    for index in 0..<frames {
      let sample = samples[index]
      sum += sample * sample
    }
    let rms = sqrt(sum / Float(frames))
    guard rms > 0 else { return 0 }

    let decibels = 20 * log10(rms)
    return Double(max(0, min(1, (decibels + 50) / 50)))
  }

  private func requestSpeechPermission() async -> Bool {
    switch SFSpeechRecognizer.authorizationStatus() {
    case .authorized:
      return true
    case .denied, .restricted:
      return false
    case .notDetermined:
      return await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { status in
          continuation.resume(returning: status == .authorized)
        }
      }
    @unknown default:
      return false
    }
  }

  private func requestMicrophonePermission() async -> Bool {
    switch AVAudioApplication.shared.recordPermission {
    case .granted:
      return true
    case .denied:
      return false
    case .undetermined:
      return await AVAudioApplication.requestRecordPermission()
    @unknown default:
      return false
    }
  }
}

private enum SpeechInputError: LocalizedError {
  case noAudioInput

  var errorDescription: String? {
    "利用できる音声入力が見つかりません。"
  }
}
