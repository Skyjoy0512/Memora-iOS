import Foundation

@main
@MainActor
struct RecordingResourceLifecycleChecks {
  static func main() {
    let model = MemoraModel()
    let process = ProcessInfo.processInfo
    let systemConserves = process.isLowPowerModeEnabled
      || process.thermalState == .serious || process.thermalState == .critical

    model.isRecording = true
    model.levelMeter.isActive = true
    model.refreshRecordingResources()
    precondition(model.recordingTicker != nil)
    precondition((model.levelTicker != nil) == !systemConserves)
    precondition(model.recorder.meteringEnabled == !systemConserves)

    let foregroundTicker = model.recordingTicker!
    let meterTicker = model.levelTicker
    model.updateRecordingResources(isForeground: false)
    precondition(foregroundTicker.isCancelled)
    precondition(meterTicker == nil || meterTicker!.isCancelled)
    precondition(model.recordingTicker == nil && model.levelTicker == nil)
    precondition(model.recordingElapsed == model.recorder.recordedDuration)
    precondition(!model.recorder.meteringEnabled && model.levelMeter.level == 0)

    // Foregrounding reads the recorder again rather than adding a guessed
    // number of missed UI timer ticks.
    model.recorder.recordedDuration = 906
    model.updateRecordingResources(isForeground: true)
    precondition(model.recordingTicker != nil)
    model.updateRecordingResources(isForeground: false)
    precondition(model.recordingElapsed == 906)
    model.updateRecordingResources(isForeground: true)

    let resumedTicker = model.recordingTicker!
    model.isRecordingPaused = true
    model.refreshRecordingResources()
    precondition(resumedTicker.isCancelled && model.recordingTicker == nil)
    precondition(model.levelTicker == nil && !model.recorder.meteringEnabled)
    precondition(!model.realtimeTranscriber.running)

    model.isRecordingPaused = false
    model.recordingPowerMode = .lowPower
    model.refreshRecordingResources()
    precondition(model.recordingConservesResources)
    precondition(model.recordingTicker != nil && model.levelTicker == nil)
    precondition(!model.recorder.meteringEnabled)
    precondition(model.realtimeTranscriber.powerSuspensions > 0)
    precondition(!model.realtimeTranscriber.running)

    model.recordingPowerMode = .standard
    RealtimeTranscriptionService.isEnabled = false
    model.refreshRecordingResources()
    precondition(!model.realtimeTranscriber.running)
    precondition(model.recordingTicker != nil)
    model.setRecordingMeterVisible(false)
    precondition(model.levelTicker == nil && !model.recorder.meteringEnabled)

    RealtimeTranscriptionService.isEnabled = true
    model.refreshRecordingResources()
    precondition(model.realtimeTranscriber.running == !systemConserves)
    precondition(model.recordingTicker != nil)
    precondition(model.recorder.stops == 0 && model.recorder.pauses == 0)
    print("RecordingResourceLifecycleChecks: passed (background, foreground, pause, mode, live OFF, hidden meter; AAC never stopped)")
  }
}

// Compile the production extension against observable service boundaries. These
// counters test resource decisions, not AVFoundation/SpeechAnalyzer behavior.
@MainActor
final class MemoraModel {
  var isRecording = false
  var isRecordingPaused = false
  var recordingIsForeground = true
  var recordingPowerMode = RecordingPowerMode.standard
  var recordingConservesResources = false
  var recordingElapsed: TimeInterval = 0
  var recordingTicker: Task<Void, Never>?
  var levelTicker: Task<Void, Never>?
  var recorder = RecorderFixture()
  var levelMeter = LevelFixture()
  var realtimeTranscriber = RealtimeTranscriptionService()

  func startRecordingTicker() { recordingTicker = Task {} }
  func startLevelTicker() { levelTicker = Task {} }
}

@MainActor
final class RecorderFixture {
  var recordedDuration: TimeInterval? = 6
  var meteringEnabled = false
  var stops = 0
  var pauses = 0
  func setMeteringEnabled(_ enabled: Bool) { meteringEnabled = enabled }
  func stop() { stops += 1 }
  func pause() { pauses += 1 }
}

@MainActor
final class LevelFixture {
  var isActive = false
  var level: Double = 0.5
  func reset() { level = 0 }
}

@MainActor
final class RealtimeTranscriptionService {
  static var isEnabled = true
  var running = false
  var powerSuspensions = 0
  func start() { running = true }
  func stop() { running = false }
  func suspendForPowerSaving() { stop(); powerSuspensions += 1 }
}
