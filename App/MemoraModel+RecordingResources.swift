import Foundation

extension MemoraModel {
  func setRecordingMeterVisible(_ visible: Bool) {
    levelMeter.isActive = visible
    refreshRecordingResources()
  }

  func updateRecordingResources(isForeground: Bool) {
    recordingIsForeground = isForeground
    refreshRecordingResources()
  }

  func refreshRecordingResources() {
    let process = ProcessInfo.processInfo
    let conserves = RecordingPowerMode.conservesResources(mode: recordingPowerMode,
      lowPower: process.isLowPowerModeEnabled,
      thermalRestricted: process.thermalState == .serious || process.thermalState == .critical)
    if recordingConservesResources != conserves { recordingConservesResources = conserves }
    if isRecordingPaused || !recordingIsForeground {
      if isRecording, let duration = recorder.recordedDuration { recordingElapsed = duration }
      recordingTicker?.cancel()
      recordingTicker = nil
    } else if isRecording && recordingTicker == nil {
      startRecordingTicker()
    }
    let analysesSilence = isRecording && !isRecordingPaused && recordingIsForeground && !conserves
    recordingSilenceWatch?.setEnabled(analysesSilence)
    if analysesSilence {
      if recordingSilenceTicker == nil { startSilenceTicker() }
    } else {
      recordingSilenceTicker?.cancel()
      recordingSilenceTicker = nil
      if isRecordingQuiet { isRecordingQuiet = false }
    }
    levelTicker?.cancel()
    levelTicker = nil
    let meters = isRecording && !isRecordingPaused && levelMeter.isActive
      && recordingIsForeground && !conserves
    recorder.setMeteringEnabled(meters)
    if meters { startLevelTicker() } else { levelMeter.reset() }
    guard isRecording else { return }
    if isRecordingPaused || conserves || !RealtimeTranscriptionService.isEnabled {
      if conserves { realtimeTranscriber.suspendForPowerSaving() }
      else { realtimeTranscriber.stop() }
    } else {
      realtimeTranscriber.start()
    }
  }
}
