import SwiftUI

/// Only this small surface observes the fast-changing microphone amplitude.
struct RecordingSheetBackground: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    ZStack(alignment: .bottom) {
      Rectangle().fill(.regularMaterial)
      VoiceGlow(level: model.levelMeter.level,
        isActive: model.isRecording && !model.isRecordingPaused
          && !model.recordingConservesResources && scenePhase == .active)
        .frame(height: 300)
    }
  }
}
