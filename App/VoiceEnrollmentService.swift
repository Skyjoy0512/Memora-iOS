import Foundation
import Observation

@MainActor
@Observable
final class VoiceEnrollmentService {
  static let minimumDuration: TimeInterval = 10
  static let maximumDuration: TimeInterval = 30

  private(set) var isPreparing = false
  private(set) var isRecording = false
  private(set) var duration: TimeInterval = 0
  private(set) var level: Double = 0
  private(set) var candidateURL: URL?
  private(set) var errorMessage: String?
  @ObservationIgnored private let recorder = AudioRecorderService()
  @ObservationIgnored private var ticker: Task<Void, Never>?
  @ObservationIgnored private var runID: UUID?
  @ObservationIgnored private var audibleTicks = 0
  @ObservationIgnored private var stopperID: UUID?

  init() {
    stopperID = AudioSessionCoordinator.shared.registerStopper(.voiceEnrollment) { [weak self] in
      self?.cancel()
    }
    recorder.onInterruption = { [weak self] _ in
      guard let self, self.isRecording else { return }
      self.finish()
      self.errorMessage = "マイクの使用が中断されました。サンプルを確認するか、もう一度録音してください。"
    }
  }

  func start() async {
    guard !isPreparing, !isRecording else { return }
    cancel()
    guard candidateURL == nil else { return }
    if stopperID == nil {
      stopperID = AudioSessionCoordinator.shared.registerStopper(.voiceEnrollment) { [weak self] in
        self?.cancel()
      }
    }
    errorMessage = nil
    let run = UUID()
    runID = run
    isPreparing = true
    defer { if runID == run { isPreparing = false } }
    let allowed = await recorder.requestPermission()
    guard runID == run, !Task.isCancelled else { return }
    guard allowed else {
      errorMessage = "マイクが許可されていません。iPhoneの設定でMemoraのマイクを許可してください。"
      return
    }
    do {
      candidateURL = try await recorder.start(purpose: .voiceEnrollment)
      guard runID == run, !Task.isCancelled else {
        cancel()
        return
      }
      isRecording = true
      ticker = Task { [weak self] in
        while !Task.isCancelled {
          guard let self, self.isRecording else { return }
          self.duration = self.recorder.elapsed
          self.level = self.recorder.level()
          if self.level > 0.2 { self.audibleTicks += 1 }
          if self.duration >= Self.maximumDuration {
            self.finish()
            return
          }
          try? await Task.sleep(for: .milliseconds(100))
        }
      }
    } catch {
      guard runID == run else { return }
      errorMessage = error.localizedDescription
    }
  }

  func finish() {
    guard isRecording else { return }
    duration = recorder.elapsed
    recorder.stop()
    ticker?.cancel()
    ticker = nil
    isRecording = false
    level = 0
    if duration < Self.minimumDuration || audibleTicks < 20 {
      errorMessage = duration < Self.minimumDuration
        ? "10秒以上、普段の声で話してください。もう一度録音できます。"
        : "音が小さいか、ほとんど入っていません。端末に近づいてもう一度録音してください。"
      discardCandidate()
    }
  }

  func didSave() {
    candidateURL = nil
    duration = 0
    errorMessage = nil
  }

  func cancel() {
    runID = nil
    ticker?.cancel()
    ticker = nil
    recorder.stop()
    isRecording = false
    isPreparing = false
    level = 0
    duration = 0
    audibleTicks = 0
    discardCandidate()
  }

  func close() {
    cancel()
    if let stopperID {
      AudioSessionCoordinator.shared.unregisterStopper(stopperID, for: .voiceEnrollment)
      self.stopperID = nil
    }
  }

  private func discardCandidate() {
    guard let candidateURL else { return }
    do {
      try VoiceProfileFiles.remove(candidateURL.lastPathComponent)
      self.candidateURL = nil
    } catch {
      errorMessage = "未登録の音声を削除できませんでした。もう一度お試しください。"
    }
  }
}
