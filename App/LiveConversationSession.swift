import AVFAudio
import Foundation
import Observation
@preconcurrency import Speech

// Adapted from Volocal's VoicePipeline (MIT). See Resources/Volocal-LICENSE.txt.
@MainActor
@Observable
final class LiveConversationSession {
  private(set) var phase = LiveVoicePhase.idle
  private(set) var transcript = ""
  private(set) var inputLevel: Double = 0
  private var authority = LiveTurnAuthority()
  private var isAwaitingInteraction = false
  private(set) var speakerEnabled = true
  @ObservationIgnored var validatesContext: (() -> Bool)?
  @ObservationIgnored var onUtterance: ((String) -> UUID?)?
  @ObservationIgnored var onInterrupt: ((UUID) -> Void)?
  @ObservationIgnored var onUnsentTranscript: ((String) -> Void)?
  @ObservationIgnored private let audio = LiveVoiceAudioEngine()
  @ObservationIgnored private let renderer = LiveSpeechRenderer()
  @ObservationIgnored private let bridge = LiveMicrophoneBridge()
  @ObservationIgnored private let recognizer = LiveVoiceRecognizer()
  @ObservationIgnored private var inputMonitor: Task<Void, Never>?
  @ObservationIgnored private var inputHealth = LiveInputHealth()
  @ObservationIgnored private var recognitionStartedAt = ProcessInfo.processInfo.systemUptime
  @ObservationIgnored private var recognitionID: UUID?
  @ObservationIgnored private var silenceTask: Task<Void, Never>?
  @ObservationIgnored private var speakingTask: Task<Void, Never>?
  @ObservationIgnored private var sessionToken: AudioSessionCoordinator.Token?
  @ObservationIgnored private var stopperID: UUID?
  @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
  @ObservationIgnored private var sentenceBuffer = LiveSentenceBuffer()
  @ObservationIgnored private var sentences: [String] = []
  @ObservationIgnored private var deliveredText = ""
  @ObservationIgnored private var generationFinished = false

  var responseID: UUID? { authority.responseID }
  var isRunning: Bool { authority.sessionID != nil }
  var isSpeaking: Bool { phase == .speaking }

  init() { installLifecycleObservers() }

  private func installLifecycleObservers() {
    if stopperID == nil {
      stopperID = AudioSessionCoordinator.shared.registerStopper(.speechInput) { [weak self] in self?.stop() }
    }
    if interruptionObserver == nil {
      interruptionObserver = NotificationCenter.default.addObserver(
        forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
      ) { [weak self] _ in Task { @MainActor in self?.pause() } }
    }
  }

  func disconnect() {
    stop()
    validatesContext = nil
    onUtterance = nil
    onInterrupt = nil
    onUnsentTranscript = nil
    if let stopperID { AudioSessionCoordinator.shared.unregisterStopper(stopperID, for: .speechInput) }
    stopperID = nil
    if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    interruptionObserver = nil
  }

  func start(unavailableReason: String? = nil) async {
    installLifecycleObservers()
    stop(preserveTranscript: false)
    if let unavailableReason { fail(unavailableReason); return }
    let run = authority.begin()
    phase = .preparing
    let speechPermission = await speechAuthorized()
    guard authority.sessionID == run, validatesContext?() == true, !Task.isCancelled else { return }
    guard speechPermission else { fail("音声認識へのアクセスを設定で許可してください。"); return }
    let microphonePermission = await AVAudioApplication.requestRecordPermission()
    guard authority.sessionID == run, validatesContext?() == true, !Task.isCancelled else { return }
    guard microphonePermission else { fail("マイクへのアクセスを設定で許可してください。"); return }
    do {
      try await recognizer.prepare {
        guard self.authority.sessionID == run, self.validatesContext?() == true else { return }
        self.phase = .loadingRecognitionModel
      }
    } catch {
      guard authority.sessionID == run, !Task.isCancelled else { return }
      recognitionFailed(error)
      return
    }
    guard authority.sessionID == run, validatesContext?() == true, !Task.isCancelled else { return }
    guard let token = AudioSessionCoordinator.shared.claim(.speechInput) else {
      fail(AudioSessionCoordinator.shared.refusal(for: .speechInput) ?? "今はLiveを開始できません。")
      return
    }
    sessionToken = token
    do {
      try audio.start(bridge: bridge)
      beginRecognition(run: run)
    } catch { fail("Liveの音声を開始できませんでした。\(error.localizedDescription)") }
  }

  func setAwaitingInteraction(_ waiting: Bool) {
    guard isRunning, responseID != nil, waiting != isAwaitingInteraction else { return }
    isAwaitingInteraction = waiting
    if waiting {
      recognitionID = nil
      recognizer.stop(bridge: bridge)
      inputMonitor?.cancel()
      inputLevel = 0
      silenceTask?.cancel()
      stopSpeaking()
      if !transcript.isEmpty, validatesContext?() == true { onUnsentTranscript?(transcript) }
      transcript = ""
      phase = .waitingForInteraction
    } else if let run = authority.sessionID {
      phase = .thinking
      beginRecognition(run: run)
    }
  }

  func requireReview() {
    stop()
    phase = .needsReview
  }

  func interruptResponse() {
    let interrupted = authority.interrupt()
    stopSpeaking()
    generationFinished = true
    if isRunning { phase = .listening }
    if let interrupted, validatesContext?() == true { onInterrupt?(interrupted) }
  }

  func pause() {
    guard isRunning else { return }
    stop()
    phase = .paused
  }

  func stop(preserveTranscript: Bool = true) {
    let interrupted = authority.responseID
    let draft = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    let contextIsCurrent = validatesContext?() == true
    authority.stop()
    isAwaitingInteraction = false
    recognitionID = nil
    recognizer.stop(bridge: bridge)
    inputMonitor?.cancel()
    inputMonitor = nil
    inputLevel = 0
    silenceTask?.cancel()
    silenceTask = nil
    stopSpeaking()
    audio.stop()
    if let sessionToken { AudioSessionCoordinator.shared.release(sessionToken) }
    sessionToken = nil
    if contextIsCurrent {
      if let interrupted { onInterrupt?(interrupted) }
      if preserveTranscript, !draft.isEmpty { onUnsentTranscript?(draft) }
    }
    transcript = ""
    phase = .idle
  }

  func setSpeakerEnabled(_ enabled: Bool) {
    speakerEnabled = enabled
    if !enabled {
      stopSpeaking()
      if isRunning { phase = generationFinished || responseID == nil ? .listening : .thinking }
    }
  }

  func receiveResponse(id: UUID, speakableText: String, isThinking: Bool) {
    guard responseID == id, !isAwaitingInteraction, let run = authority.sessionID else { return }
    guard validatesContext?() == true else { stop(); return }
    guard speakableText.hasPrefix(deliveredText) else {
      // Revisions never replay already-spoken text or stale queued audio.
      stopSpeaking()
      deliveredText = speakableText
      generationFinished = !isThinking
      if !isThinking { completeIfSilent() }
      return
    }
    let tail = String(speakableText.dropFirst(deliveredText.count))
    if deliveredText.isEmpty, !speakableText.isEmpty { print("[Live] AI response received") }
    deliveredText = speakableText
    let ready = sentenceBuffer.append(tail)
    if speakerEnabled { sentences.append(contentsOf: ready) }
    generationFinished = !isThinking
    if generationFinished {
      let remaining = sentenceBuffer.flush()
      if speakerEnabled { sentences.append(contentsOf: remaining) }
    }
    if sentences.count > 32 {
      fail("読み上げが追いつかなかったためLiveを停止しました。回答は会話に残っています。")
      return
    }
    pumpSpeech(run: run)
    completeIfSilent()
  }

  private func beginRecognition(run: UUID) {
    inputMonitor?.cancel()
    inputLevel = 0
    let recognition = UUID()
    recognitionID = recognition
    inputMonitor = Task { [weak self] in
      try? await Task.sleep(for: .seconds(30))
      guard !Task.isCancelled, let self, self.authority.sessionID == run,
            self.recognitionID == recognition else { return }
      self.fail("日本語の音声認識の準備に時間がかかっています。Liveを再開してください。")
    }
    guard let format = audio.inputFormat else { fail("マイクの入力形式を取得できません。Liveを再開してください。"); return }
    recognizer.start(format: format, bridge: bridge) { [weak self] in
      guard let self, self.authority.sessionID == run, self.recognitionID == recognition else { return }
      self.monitorInput(run: run, recognition: recognition)
    } onText: { [weak self] text in
      guard let self, self.authority.sessionID == run, self.recognitionID == recognition else { return }
      guard self.validatesContext?() == true else { self.stop(); return }
      self.inputHealth.receivedResult(at: ProcessInfo.processInfo.systemUptime - self.recognitionStartedAt)
      if self.transcript.isEmpty { print("[Live] speech recognised; no transcript logged") }
      self.acceptPartial(text, run: run, recognition: recognition)
    } onFailure: { [weak self] error in
      guard let self, self.authority.sessionID == run, self.recognitionID == recognition else { return }
      self.recognitionFailed(error)
    }
  }

  private func monitorInput(run: UUID, recognition: UUID) {
    inputMonitor?.cancel()
    inputHealth = LiveInputHealth()
    recognitionStartedAt = ProcessInfo.processInfo.systemUptime
    inputMonitor = Task { [weak self] in
      var receivedAudio = false
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled, let self, self.authority.sessionID == run,
              self.recognitionID == recognition else { return }
        guard self.validatesContext?() == true else { self.stop(); return }
        let snapshot = self.bridge.snapshot()
        let level = snapshot.peak > 0 ? max(0, min(1, (20 * log10(Double(snapshot.peak)) + 55) / 45)) : 0
        self.inputLevel = level
        if !receivedAudio, snapshot.frames > 0 {
          receivedAudio = true
          print("[Live] microphone buffers received")
          if self.responseID == nil { self.phase = .listening }
        }
        let expectsRecognition = self.responseID == nil && self.phase != .speaking
        if let failure = self.inputHealth.check(elapsed: ProcessInfo.processInfo.systemUptime - self.recognitionStartedAt,
          frames: snapshot.frames, voicedSeconds: snapshot.voicedSeconds, expectsRecognition: expectsRecognition) {
          print("[Live] input stopped: \(failure)")
          self.fail(failure.message)
          return
        }
      }
    }
  }

  private func recognitionFailed(_ error: Error) {
    let nsError = error as NSError
    print("[Live] recognition failed: domain=\(nsError.domain) code=\(nsError.code)")
    if let error = error as? LiveVoiceError { fail(error.localizedDescription); return }
    #if targetEnvironment(simulator)
    fail("このプレビューでは日本語の音声認識を開始できませんでした。実際のiPhoneでLiveをお試しください。")
    #else
    fail("日本語の音声認識を準備できませんでした。インターネット接続と端末の空き容量を確認して、Liveを再開してください。")
    #endif
  }

  private func acceptPartial(_ text: String, run: UUID, recognition: UUID) {
    let changed = transcript != text
    transcript = text
    if authority.responseID != nil, text.filter({ !$0.isWhitespace && !$0.isPunctuation }).count >= 3 {
      let interrupted = authority.interrupt()
      stopSpeaking()
      phase = .listening
      if let interrupted { onInterrupt?(interrupted) }
    }
    guard changed else { return }
    silenceTask?.cancel()
    silenceTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(1_000))
      guard !Task.isCancelled else { return }
      self?.commitUtterance(run: run, recognition: recognition)
    }
  }

  private func commitUtterance(run: UUID, recognition: UUID) {
    guard authority.sessionID == run, recognitionID == recognition, !isAwaitingInteraction,
          validatesContext?() == true else { return }
    silenceTask?.cancel()
    let utterance = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !utterance.isEmpty else { return }
    if let interrupted = authority.interrupt() { onInterrupt?(interrupted) }
    stopSpeaking()
    transcript = ""
    // Start a fresh recognition request on the same echo-cancelled audio engine.
    beginRecognition(run: run)
    guard let id = onUtterance?(utterance) else {
      stop(preserveTranscript: false)
      phase = .needsReview
      return
    }
    guard authority.sessionID == run, validatesContext?() == true else { return }
    print("[Live] utterance submitted to selected AI")
    authority.attachResponse(id)
    deliveredText = ""
    generationFinished = false
    phase = .thinking
  }

  private func pumpSpeech(run: UUID) {
    guard speakingTask == nil, !sentences.isEmpty, speakerEnabled else { return }
    let revision = authority.revision
    phase = .speaking
    speakingTask = Task { [weak self] in
      guard let self else { return }
      do {
        while !self.sentences.isEmpty {
          guard !Task.isCancelled, self.authority.allows(session: run, revision: revision),
                self.validatesContext?() == true else { return }
          let sentence = self.sentences.removeFirst()
          for try await chunk in try self.renderer.stream(sentence) {
            while self.audio.queuedSeconds > 2 {
              try await Task.sleep(for: .milliseconds(25))
              guard self.authority.allows(session: run, revision: revision), self.validatesContext?() == true else { return }
            }
            try Task.checkCancellation()
            guard self.authority.allows(session: run, revision: revision), self.validatesContext?() == true else { return }
            try self.audio.schedule(chunk)
          }
          while self.audio.queuedSeconds > 0 {
            try await Task.sleep(for: .milliseconds(25))
            guard self.authority.allows(session: run, revision: revision), self.validatesContext?() == true else { return }
          }
        }
        guard self.authority.allows(session: run, revision: revision) else { return }
        self.speakingTask = nil
        self.phase = self.generationFinished ? .listening : .thinking
        self.completeIfSilent()
      } catch {
        guard !Task.isCancelled, self.authority.allows(session: run, revision: revision) else { return }
        self.fail("Liveの読み上げが中断されました。\(error.localizedDescription)")
      }
    }
  }

  private func completeIfSilent() {
    guard !isAwaitingInteraction, generationFinished, speakingTask == nil, sentences.isEmpty else { return }
    authority.interrupt()
    phase = .listening
  }

  private func stopSpeaking() {
    speakingTask?.cancel()
    speakingTask = nil
    renderer.stop()
    audio.stopPlayback()
    sentences.removeAll()
    sentenceBuffer.reset()
  }

  private func fail(_ reason: String) {
    stop()
    phase = .failed(reason)
  }

  private func speechAuthorized() async -> Bool {
    switch SFSpeechRecognizer.authorizationStatus() {
    case .authorized: true
    case .denied, .restricted: false
    case .notDetermined:
      await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
      }
    @unknown default: false
    }
  }
}
