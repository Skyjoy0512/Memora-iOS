import AVFAudio
import Foundation
import Synchronization

@MainActor
final class AudioRecorderService: NSObject, AVAudioRecorderDelegate {
  enum Purpose {
    case recording
    case voiceEnrollment
  }

  /// A recording prepared before the microphone opens, so the manifest and
  /// draft can be written to the store first.
  struct PreparedRecording {
    var manifest: RecordingAudioManifest
    var directory: URL
    var fileURL: URL
  }

  /// Thread-safe state written by the input tap and read on the main actor.
  private final class ContinuousSink: @unchecked Sendable {
    let writer: RecordingChunkWriter
    let frames = Mutex<Int64>(0)
    let level = Mutex<Float>(0)

    init(writer: RecordingChunkWriter) {
      self.writer = writer
    }

    func append(_ output: RecordingMicrophoneInput.Output) -> Bool {
      let accepted = writer.append(output.buffer)
      guard accepted else { return false }
      frames.withLock { $0 += Int64(output.buffer.frameLength) }
      level.withLock { $0 = Self.rms(output.buffer) }
      return true
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
      guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
      let count = Int(buffer.frameLength)
      let stride = max(1, count / 512)
      var sum: Float = 0
      var used = 0
      var index = 0
      while index < count {
        let sample = samples[index]
        sum += sample * sample
        used += 1
        index += stride
      }
      let rms = sqrt(sum / Float(max(used, 1)))
      return min(1, max(0, rms * 4))
    }
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
    if isContinuous {
      if let continuousSink {
        let frames = continuousSink.frames.withLock { $0 }
        lastRecordedDuration = max(lastRecordedDuration ?? 0, Double(frames) / 44_100)
      }
      return lastRecordedDuration
    }
    if let seconds = recorder?.currentTime, seconds.isFinite, seconds >= 0 {
      lastRecordedDuration = max(lastRecordedDuration ?? 0, seconds)
    }
    return lastRecordedDuration
  }
  private var observers: [NSObjectProtocol] = []
  private let coordinator: AudioSessionCoordinator
  /// The session claim this recorder holds, so only this run can give it up.
  private var sessionToken: AudioSessionCoordinator.Token?
  /// Continuous (engine + chunk writer) capture, used for normal recordings.
  private var microphone: RecordingMicrophoneInput?
  private var writer: RecordingChunkWriter?
  private var continuousSink: ContinuousSink?
  private var isContinuous = false
  private var writingDirectory: URL?

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

  /// Builds the first manifest and its destination without touching the
  /// microphone. The caller persists a draft from this before `startContinuous`.
  func prepareRecording() throws -> PreparedRecording {
    let directory = try recordingsDirectory()
    guard try SourceMediaStaging.availableBytes(directory) >= SourceMediaStaging.minimumAvailableBytes else {
      throw SourceMediaFailure.capacity
    }
    let recordingID = UUID()
    let fileName = "Memora-\(UUID().uuidString).m4a"
    return PreparedRecording(
      manifest: .starting(id: recordingID, fileName: fileName),
      directory: directory,
      fileURL: directory.appendingPathComponent(fileName))
  }

  /// Takes the session and starts the engine tap feeding a 15-minute chunk
  /// writer. `admitRotation` must durably persist the next manifest before the
  /// writer opens the next original.
  func startContinuous(_ prepared: PreparedRecording,
                       admitRotation: @escaping @Sendable (RecordingRotation) async -> Bool,
                       liveSink: (@Sendable (RecordingMicrophoneInput.Output) -> Void)? = nil) async throws -> URL {
    guard recorder == nil, writer == nil, microphone == nil, let runID = run.begin() else {
      throw AudioRecorderError.sessionBusy
    }
    lastFailureReason = nil
    guard let token = await coordinator.beginRecording() else {
      run.cancel(runID)
      throw AudioRecorderError.sessionBusy
    }
    guard run.owns(runID), !Task.isCancelled else {
      run.cancel(runID)
      coordinator.endRecording(token)
      throw CancellationError()
    }
    sessionToken = token
    lastRecordedDuration = nil
    isContinuous = true
    writingDirectory = prepared.directory
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
      try session.setActive(true)
      guard session.isInputAvailable else { throw AudioRecorderError.couldNotStart }
      let diagnosticSession = AudioProcessingDiagnostics.begin(.recording)
      diagnostic = diagnosticSession
      let writer = try RecordingChunkWriter(manifest: prepared.manifest, directory: prepared.directory,
        diagnostic: diagnosticSession, admitRotation: admitRotation)
      let sink = ContinuousSink(writer: writer)
      let microphone = RecordingMicrophoneInput(
        sink: { @Sendable output in sink.append(output) },
        liveSink: liveSink,
        onFailure: { @Sendable [weak self] failure in
          Task { @MainActor [weak self] in self?.handleContinuousFailure(failure) }
        })
      try microphone.start()
      guard run.markRecording(runID) else {
        microphone.stop()
        writer.cancel()
        throw AudioRecorderError.couldNotStart
      }
      self.writer = writer
      self.continuousSink = sink
      self.microphone = microphone
      diagnosticOutcome = .success
      monitorContinuousStorage()
      return prepared.fileURL
    } catch {
      microphone = nil
      writer?.cancel()
      writer = nil
      continuousSink = nil
      isContinuous = false
      writingDirectory = nil
      run.cancel(runID)
      finishDiagnostic(.failed)
      releaseSession()
      throw error
    }
  }

  /// Stops the tap, drains every accepted buffer into the writer, and returns
  /// the writer's verified manifest. The caller persists and inspects it.
  @discardableResult
  func stopContinuous() async -> RecordingAudioManifest? {
    storageMonitor?.cancel()
    storageMonitor = nil
    microphone?.stop()
    microphone = nil
    guard let writer else {
      continuousSink = nil
      isContinuous = false
      writingDirectory = nil
      if let id = run.runID { run.cancel(id) }
      run.reset()
      releaseSession()
      return nil
    }
    if let id = run.runID, run.beginStopping(id) { run.beginFinalizing(id) }
    let result = await writer.finish()
    self.writer = nil
    continuousSink = nil
    isContinuous = false
    writingDirectory = nil
    if let id = run.runID {
      if result.isComplete {
        lastRecordedDuration = result.manifest.finalizedDuration
        run.markSaved(id)
      } else {
        lastFailureReason = "音声の書き込みを完了できませんでした。残っている音声とメモを保存します。"
        run.fail(id, reason: lastFailureReason ?? "")
      }
    }
    run.reset()
    releaseSession()
    finishDiagnostic(result.isComplete ? .success : .failed)
    return result.manifest
  }

  /// Discards a continuous run without draining or committing it.
  func cancelContinuous() {
    storageMonitor?.cancel()
    storageMonitor = nil
    microphone?.stop()
    microphone = nil
    writer?.cancel()
    writer = nil
    continuousSink = nil
    isContinuous = false
    writingDirectory = nil
    if let id = run.runID { run.cancel(id) }
    run.reset()
    releaseSession()
    finishDiagnostic(.cancelled)
  }

  private func handleContinuousFailure(_ failure: RecordingMicrophoneInput.Failure) {
    guard let id = run.runID else { return }
    let reason = switch failure {
    case .noInput: "マイクの入力を確認できませんでした。ここまでの音声を保存します。"
    case .unsupportedFormat: "この入力形式には対応していません。ここまでの音声を保存します。"
    case .conversion: "音声の変換に失敗しました。ここまでの音声を保存します。"
    case .inputGap: "音声の一部が途切れました。ここまでの音声を保存します。"
    case .inputDuplicate: "音声の入力が重複しました。ここまでの音声を保存します。"
    case .overrun: "音声の書き込みが追いつきませんでした。ここまでの音声を保存します。"
    }
    lastFailureReason = reason
    diagnosticOutcome = .failed
    guard run.fail(id, reason: reason) else { return }
    microphone?.stop()
    storageMonitor?.cancel()
    storageMonitor = nil
    onInterruption?(.failed(reason))
  }

  private func monitorContinuousStorage() {
    storageMonitor?.cancel()
    guard let directory = writingDirectory else { return }
    storageMonitor = Task { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(15)) }
        catch { return }
        guard let self, await self.checkContinuousStorage(directory: directory) else { return }
      }
    }
  }

  private func checkContinuousStorage(directory: URL) async -> Bool {
    guard !Task.isCancelled, isContinuous, run.phase == .recording else { return false }
    diagnostic?.setAudioSeconds(recordedDuration)
    if (try? SourceMediaStaging.availableBytes(directory)) ?? 0 < SourceMediaStaging.minimumAvailableBytes {
      diagnostic?.count(.storageStop)
      lastFailureReason = "空き容量が少なくなったため録音を停止します。ここまでの音声を保存します。古い記録は削除しません。"
      if let id = run.runID { run.fail(id, reason: lastFailureReason ?? "") }
      onInterruption?(.failed(lastFailureReason ?? ""))
      return false
    }
    let saved = if let onCheckpoint { await onCheckpoint() } else { true }
    guard !Task.isCancelled, isContinuous, run.phase == .recording else { return false }
    if !saved {
      diagnostic?.count(.draftCheckpointFailure)
      lastFailureReason = "録音の復旧情報を保存できないため録音を停止します。残っている音声とメモを保存します。ストレージの空き容量を確認してください。"
      if let id = run.runID { run.fail(id, reason: lastFailureReason ?? "") }
      onInterruption?(.failed(lastFailureReason ?? ""))
      return false
    }
    return true
  }

  private func finishDiagnostic(_ outcome: AudioDiagnosticReport.Outcome) {
    guard let diagnostic else { return }
    diagnostic.setAudioSeconds(lastRecordedDuration)
    Task {
      diagnostic.sample(await AudioResourceProbe.capture())
      diagnostic.finish(outcome)
    }
    self.diagnostic = nil
  }

  func stop() {
    // Continuous capture must drain through stopContinuous(); a plain stop here
    // would release the session without writing what the writer accepted.
    if isContinuous {
      cancelContinuous()
      return
    }
    storageMonitor?.cancel()
    storageMonitor = nil
    // Only a live capture drains and finalizes; a failed, cancelled or already
    // stopped run must not be reported as saved here.
    if let id = run.runID {
      switch run.phase {
      case .recording:
        if run.beginStopping(id) { run.beginFinalizing(id) }
      case .preparing:
        run.cancel(id)
      case .stopping:
        run.beginFinalizing(id)
      case .idle, .finalizing, .saved, .failed, .cancelled:
        break
      }
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
    if let id = run.runID, run.phase == .finalizing { run.markSaved(id) }
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
    if isContinuous { return Double(continuousSink?.level.withLock { $0 } ?? 0) }
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
    if isContinuous {
      if run.phase == .recording { diagnostic?.count(.recordingPause) }
      _ = recordedDuration
      microphone?.stop()
      return
    }
    if recorder?.isRecording == true { diagnostic?.count(.recordingPause) }
    _ = recordedDuration
    recorder?.pause()
  }

  func resume() -> Bool {
    if isContinuous {
      guard run.phase == .recording, let microphone else { return false }
      do {
        try microphone.start(resetTimeline: false)
      } catch {
        return false
      }
      diagnostic?.count(.recordingResume)
      return true
    }
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
    guard let active = recorder, ObjectIdentifier(active) == identity, run.phase == .recording else { return false }
    diagnostic?.setAudioSeconds(recordedDuration)
    if (try? SourceMediaStaging.availableBytes(directory)) ?? 0 < SourceMediaStaging.minimumAvailableBytes {
      diagnostic?.count(.storageStop)
      handleUnexpectedStop(identity: identity,
        reason: "空き容量が少なくなったため録音を停止します。ここまでの音声を保存します。古い記録は削除しません。")
      return false
    }
    let saved = if let onCheckpoint { await onCheckpoint() } else { true }
    guard !Task.isCancelled, let active = recorder, ObjectIdentifier(active) == identity,
          run.phase == .recording else { return false }
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
          guard let self, self.recorder != nil || self.isContinuous else { return }
          self.diagnostic?.count(.audioReset)
          self.diagnosticOutcome = .interrupted
          _ = self.recordedDuration
          if let id = self.run.runID {
            let reason = "オーディオがリセットされました。"
            self.lastFailureReason = reason
            self.run.fail(id, reason: reason)
          }
          if self.isContinuous {
            // The engine cannot be trusted after a reset. Stop the tap; the
            // writer still drains what it already accepted.
            self.microphone?.stop()
          } else {
            self.recorder?.delegate = nil
            self.recorder = nil
          }
          self.onInterruption?(.reset)
        }
      }
    )
  }

  private func handleInterruption(_ note: Notification) {
    guard recorder != nil || isContinuous else { return }
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
    guard recorder != nil || isContinuous else { return }
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
