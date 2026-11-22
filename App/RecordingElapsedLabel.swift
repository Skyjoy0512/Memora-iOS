import SwiftUI

/// Keep the once-a-second tick local while the editors and transcript are open.
struct RecordingElapsedLabel: View {
  @Environment(MemoraModel.self) private var model
  var compact = false

  var body: some View {
    let layout = compact
      ? AnyLayout(HStackLayout(spacing: MemoraSpacing.md))
      : AnyLayout(VStackLayout(spacing: MemoraSpacing.xs))
    let duration = MemoraFormat.duration(model.recordingElapsed)
    layout {
      HStack(spacing: MemoraSpacing.xs) {
        Circle()
          .fill(model.isRecordingPaused || model.isSavingCapture ? Color.secondary : Color.red)
          .frame(width: 7, height: 7)
          .accessibilityHidden(true)
        Text(status)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Text(duration)
        .font((compact ? Font.headline : .largeTitle).monospacedDigit().weight(.semibold))
        .accessibilityLabel("録音時間 \(duration)")
    }
  }

  private var status: String {
    if model.isSavingCapture { return "保存しています…" }
    return model.isRecordingPaused ? "一時停止中" : "録音中"
  }
}
