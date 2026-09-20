import AVFAudio
import Foundation
import Observation
import Speech

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

  func toggle(transcriptChanged: @escaping @MainActor (String) -> Void) async {
    if isListening {
      stop()
    } else {
      await start(transcriptChanged: transcriptChanged)
    }
  }

  func stop() {
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
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
    errorMessage = nil

    guard await requestSpeechPermission() else {
      errorMessage = "音声認識へのアクセスを設定で許可してください。"
      return
    }
    guard await requestMicrophonePermission() else {
      errorMessage = "マイクへのアクセスを設定で許可してください。"
      return
    }
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP")), recognizer.isAvailable else {
      errorMessage = "音声入力を利用できません。通信状態を確認してください。"
      return
    }

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
      inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
        request.append(buffer)
        let level = Self.loudness(of: buffer)
        Task { @MainActor [weak self] in
          self?.apply(level: level)
        }
      }
      hasInstalledInputTap = true

      recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
        Task { @MainActor in
          if let result {
            transcriptChanged(result.bestTranscription.formattedString)
          }
          if result?.isFinal == true || error != nil {
            self?.stop()
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
