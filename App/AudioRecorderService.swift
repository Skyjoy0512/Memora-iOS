import AVFAudio
import Foundation

@MainActor
final class AudioRecorderService: NSObject, AVAudioRecorderDelegate {
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
    case failed(String)
  }

  /// Called when the session is interrupted or the input goes away, so the
  /// caller can keep its state honest and let the person resume.
  var onInterruption: ((Interruption) -> Void)?
  var onCheckpoint: (() async -> Bool)?

  private var recorder: AVAudioRecorder?
  /// Guards the capture run so a double start/stop or a late callback from an
  /// older run cannot move the state of a newer one.
  private var run = RecordingRunCoordinator()
  private var lastRecordedDuration: TimeInterval?
  private(set) var lastFailureReason: String?
  private var storageMonitor: Task<Void, Never>?
  private var diagnostic: AudioDiagnosticSession?
  private var diagnosticOutcome: AudioDiagnosticReport.Outcome = .success
  var recordedDuration: TimeInterval? {
    if let seconds = recorder?.currentTime, seconds.isFinite, seconds >= 0 {
      lastRecordedDuration = max(lastRecordedDuration ?? 0, seconds)
    }
    return lastRecordedDuration
  }
  private var observers: [NSObjectProtocol] = []
  private let coordinator: AudioSessionCoordinator
  /// The session claim this recorder holds, so only this run can give it up.
  private var sessionToken: AudioSessionCoordinator.Token?

  init(coordinator: AudioSessionCoordinator? = nil) {
    self.coordinator = coordinator ?? .shared
    super.init()
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
    guard recorder == nil, let runID = run.begin() else { throw AudioRecorderError.sessionBusy }
    lastFailureReason = nil
    let token: AudioSessionCoordinator.Token
    switch purpose {
    case .recording:
      guard let claimed = await coordinator.beginRecording() else {
        run.cancel(runID)
        throw AudioRecorderError.sessionBusy
      }
      token = claimed
    case .voiceEnrollment:
      guard let claimed = coordinator.claim(.voiceEnrollment) else {
        run.cancel(runID)
        throw AudioRecorderError.sessionBusy
      }
      token = claimed
    }
    guard run.owns(runID), !Task.isCancelled else {
      run.cancel(runID)
      if token.use == .recording {
        coordinator.endRecording(token)
      } else {
        coordinator.release(token)
      }
      throw CancellationError()
    }
    sessionToken = token
    lastRecordedDuration = nil
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
      guard try SourceMediaStaging.availableBytes(directory) >= SourceMediaStaging.minimumAvailableBytes else {
        throw SourceMediaFailure.capacity
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
      recorder.delegate = self
      recorder.isMeteringEnabled = purpose == .voiceEnrollment
      guard recorder.prepareToRecord(), recorder.record() else {
        throw AudioRecorderError.couldNotStart
      }
      guard run.markRecording(runID) else {
        recorder.stop()
        throw AudioRecorderError.couldNotStart
      }
      self.recorder = recorder
      if purpose == .recording {
        diagnostic = AudioProcessingDiagnostics.begin(.recording)
        diagnosticOutcome = .success
        monitorStorage(for: recorder)
      }
      return url
    } catch {
      run.cancel(runID)
      releaseSession()
      if let destination { try? FileManager.default.removeItem(at: destination) }
      throw error
    }
  }

  func stop() {
    storageMonitor?.cancel()
    storageMonitor = nil
    // Only a live capture drains and finalizes; a failed, cancelled or already
    // stopped run must not be reported as saved here.
    if let id = run.runID, run.owns(id) {
      if run.beginStopping(id) { run.beginFinalizing(id) }
    }
    _ = recordedDuration
    if let diagnostic {
      diagnostic.setAudioSeconds(lastRecordedDuration)
      let outcome = diagnosticOutcome
      Task {
        diagnostic.sample(await AudioResourceProbe.capture())
        diagnostic.finish(outcome)
      }
      self.diagnostic = nil
    }
    recorder?.delegate = nil
    recorder?.stop()
    recorder = nil
    if let id = run.runID { run.markSaved(id) }
    run.reset()
    releaseSession()
  }

  /// Hands the session back for this run's claim alone.
  private func releaseSession() {
    guard let sessionToken else { return }
    if sessionToken.use == .recording {
      coordinator.endRecording(sessionToken)
    } else {
      coordinator.release(sessionToken)
    }
    self.sessionToken = nil
  }

  /// 0...1 loudness for the voice glow.
  func level() -> Double {
    guard let recorder, recorder.isRecording, recorder.isMeteringEnabled else { return 0 }
    recorder.updateMeters()
    let decibels = Double(recorder.averagePower(forChannel: 0))
    return max(0, min(1, (decibels + 50) / 50))
  }

  var elapsed: TimeInterval { recordedDuration ?? 0 }

  func setMeteringEnabled(_ enabled: Bool) {
    recorder?.isMeteringEnabled = enabled
  }

  func pause() {
    if recorder?.isRecording == true { diagnostic?.count(.recordingPause) }
    _ = recordedDuration
    recorder?.pause()
  }

  func resume() -> Bool {
    guard let recorder, run.phase == .recording, let sessionToken,
          coordinator.owns(sessionToken) else { return false }
    do {
      try AVAudioSession.sharedInstance().setActive(true)
      guard AVAudioSession.sharedInstance().isInputAvailable else { return false }
    } catch {
      return false
    }
    let resumed = recorder.record()
    if resumed { diagnostic?.count(.recordingResume) }
    return resumed
  }

  nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
    let identity = ObjectIdentifier(recorder)
    Task { @MainActor [weak self] in
      self?.handleUnexpectedStop(identity: identity, reason: flag
        ? "録音が停止しました。ここまでの音声を保存します。"
        : "録音を続けられなくなりました。残っている音声を保存します。")
    }
  }

  nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
    let identity = ObjectIdentifier(recorder)
    Task { @MainActor [weak self] in
      self?.handleUnexpectedStop(identity: identity,
        reason: "音声の書き込みに失敗しました。残っている音声を保存します。ストレージの空き容量を確認してください。")
    }
  }

  private func handleUnexpectedStop(identity: ObjectIdentifier, reason: String) {
    guard let recorder, ObjectIdentifier(recorder) == identity,
          let runID = run.runID, run.fail(runID, reason: reason) else { return }
    _ = recordedDuration
    lastFailureReason = reason
    diagnosticOutcome = .failed
    recorder.pause()
    storageMonitor?.cancel()
    storageMonitor = nil
    onInterruption?(.failed(reason))
  }

  private func monitorStorage(for recorder: AVAudioRecorder) {
    let identity = ObjectIdentifier(recorder)
    let directory = recorder.url.deletingLastPathComponent()
    storageMonitor?.cancel()
    storageMonitor = Task { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(15)) }
        catch { return }
        guard let self, await self.checkStorageAndDraft(identity: identity, directory: directory) else { return }
      }
    }
  }

  private func checkStorageAndDraft(identity: ObjectIdentifier, directory: URL) async -> Bool {
    guard !Task.isCancelled else { return false }
    guard let active = recorder, ObjectIdentifier(active) == identity, !hasReportedFailure else { return false }
    diagnostic?.setAudioSeconds(recordedDuration)
    if (try? SourceMediaStaging.availableBytes(directory)) ?? 0 < SourceMediaStaging.minimumAvailableBytes {
      diagnostic?.count(.storageStop)
      handleUnexpectedStop(identity: identity,
        reason: "空き容量が少なくなったため録音を停止します。ここまでの音声を保存します。古い記録は削除しません。")
      return false
    }
    let saved = if let onCheckpoint { await onCheckpoint() } else { true }
    guard !Task.isCancelled, let active = recorder, ObjectIdentifier(active) == identity, !hasReportedFailure else { return false }
    if !saved {
      diagnostic?.count(.draftCheckpointFailure)
      handleUnexpectedStop(identity: identity,
        reason: "録音の復旧情報を保存できないため録音を停止します。残っている音声とメモを保存します。ストレージの空き容量を確認してください。")
      return false
    }
    return true
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
          guard let self, self.recorder != nil else { return }
          self.diagnostic?.count(.audioReset)
          self.diagnosticOutcome = .interrupted
          _ = self.recordedDuration
          self.recorder?.delegate = nil
          self.recorder = nil
          self.onInterruption?(.reset)
        }
      }
    )
  }

  private func handleInterruption(_ note: Notification) {
    guard recorder != nil else { return }
    guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

    switch type {
    case .began:
      diagnostic?.count(.audioInterruption)
      pause()
      onInterruption?(.began)
    case .ended:
      onInterruption?(.ended)
    @unknown default:
      break
    }
  }

  private func handleRouteChange(_ note: Notification) {
    guard recorder != nil else { return }
    guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }

    guard reason == .oldDeviceUnavailable else { return }
    diagnostic?.count(.inputLost)
    pause()
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
      "マイクを使用中です。別の録音・再生・音声入力を終えてから、もう一度お試しください。"
    }
  }
}
