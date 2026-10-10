import AVFAudio
import Foundation

@MainActor
final class AudioRecorderService {
  enum Purpose {
    case recording
    case voiceEnrollment
  }

  /// Something the system did to the audio session while recording.
  enum Interruption {
    case began
    case ended
    case inputLost(String)
    case reset
  }

  /// Called when the session is interrupted or the input goes away, so the
  /// caller can keep its state honest and let the person resume.
  var onInterruption: ((Interruption) -> Void)?

  private var recorder: AVAudioRecorder?
  private var observers: [NSObjectProtocol] = []
  /// The session claim this recorder holds, so only this run can give it up.
  private var sessionToken: AudioSessionCoordinator.Token?

  init() {
    observeSession()
  }

  deinit {
    observers.forEach { NotificationCenter.default.removeObserver($0) }
  }

  func requestPermission() async -> Bool {
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

  func start(purpose: Purpose = .recording) async throws -> URL {
    // Recording waits for anything else using the session to stop, then takes it
    // and keeps it until it stops, so another feature cannot switch the audio off
    // underneath it. Every failure below hands the claim back.
    guard recorder == nil else { throw AudioRecorderError.couldNotStart }
    switch purpose {
    case .recording:
      sessionToken = await AudioSessionCoordinator.shared.beginRecording()
    case .voiceEnrollment:
      guard let token = AudioSessionCoordinator.shared.claim(.voiceEnrollment) else {
        throw AudioRecorderError.sessionBusy
      }
      sessionToken = token
    }
    var destination: URL?
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
      try session.setActive(true)
      guard session.isInputAvailable else { throw AudioRecorderError.couldNotStart }

      let directory = switch purpose {
      case .recording: try recordingsDirectory()
      case .voiceEnrollment: try VoiceProfileFiles.prepareDirectory()
      }
      let url = directory.appendingPathComponent("Memora-\(UUID().uuidString).m4a")
      destination = url
      let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
      ]
      let recorder = try AVAudioRecorder(url: url, settings: settings)
      recorder.isMeteringEnabled = true
      guard recorder.prepareToRecord(), recorder.record() else {
        throw AudioRecorderError.couldNotStart
      }
      self.recorder = recorder
      return url
    } catch {
      releaseSession()
      if let destination { try? FileManager.default.removeItem(at: destination) }
      throw error
    }
  }

  func stop() {
    recorder?.stop()
    recorder = nil
    releaseSession()
  }

  /// Hands the session back for this run's claim alone.
  private func releaseSession() {
    guard let sessionToken else { return }
    if sessionToken.use == .recording {
      AudioSessionCoordinator.shared.endRecording(sessionToken)
    } else {
      AudioSessionCoordinator.shared.release(sessionToken)
    }
    self.sessionToken = nil
  }

  /// 0...1 loudness for the voice glow.
  func level() -> Double {
    guard let recorder else { return 0 }
    recorder.updateMeters()
    let decibels = Double(recorder.averagePower(forChannel: 0))
    return max(0, min(1, (decibels + 50) / 50))
  }

  var elapsed: TimeInterval { recorder?.currentTime ?? 0 }

  func pause() {
    recorder?.pause()
  }

  func resume() -> Bool {
    // After an interruption the session has to be active again, under a fresh
    // claim so an older run's token cannot end the recording. This recorder
    // already owns it, so there is nothing to stop first.
    sessionToken = AudioSessionCoordinator.shared.takeRecordingSession()
    do {
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      releaseSession()
      return false
    }
    let started = recorder?.record() ?? false
    if !started {
      releaseSession()
    }
    return started
  }

  private func observeSession() {
    let center = NotificationCenter.default
    let session = AVAudioSession.sharedInstance()

    observers.append(
      center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
        MainActor.assumeIsolated { self?.handleInterruption(note) }
      }
    )
    observers.append(
      center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] note in
        MainActor.assumeIsolated { self?.handleRouteChange(note) }
      }
    )
    observers.append(
      center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.recorder = nil
          self?.onInterruption?(.reset)
        }
      }
    )
  }

  private func handleInterruption(_ note: Notification) {
    guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

    switch type {
    case .began:
      recorder?.pause()
      onInterruption?(.began)
    case .ended:
      onInterruption?(.ended)
    @unknown default:
      break
    }
  }

  private func handleRouteChange(_ note: Notification) {
    guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }

    guard reason == .oldDeviceUnavailable else { return }
    recorder?.pause()
    onInterruption?(.inputLost("オーディオ機器が外れたため、録音を一時停止しました。「再開」で続けられます。"))
  }

  private func recordingsDirectory() throws -> URL {
    let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let directory = base.appendingPathComponent("Recordings", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }
}

private enum AudioRecorderError: LocalizedError {
  case couldNotStart
  case sessionBusy

  var errorDescription: String? {
    switch self {
    case .couldNotStart:
      "録音を開始できませんでした。オーディオ入力を確認して、もう一度お試しください。"
    case .sessionBusy:
      "マイクを使用中です。録音・再生・音声入力を終えてから声を登録してください。"
    }
  }
}
