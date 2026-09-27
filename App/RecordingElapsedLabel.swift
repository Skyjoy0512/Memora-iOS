import SwiftUI

/// The recording sheet's dot and running time. Its own view so the once-a-second
/// tick redraws only this label, not the notes and live transcript around it.
struct RecordingElapsedLabel: View {
  @Environment(MemoraModel.self) private var model

  var body: some View {
    HStack(spacing: 8) {
      Circle()
        .fill(model.isRecordingPaused ? Color.secondary : Color.red)
        .frame(width: 8, height: 8)

      Text(MemoraFormat.duration(model.recordingElapsed))
        .font(.subheadline.monospacedDigit().weight(.semibold))
        .contentTransition(.numericText())
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("録音時間 \(MemoraFormat.duration(model.recordingElapsed))")
  }
}
