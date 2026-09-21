import ActivityKit
import SwiftUI
import WidgetKit

struct MemoraRecordingLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: MemoraRecordingAttributes.self) { context in
      MemoraLiveActivityView(context: context)
        .activityBackgroundTint(Color.primary.opacity(0.12))
        .activitySystemActionForegroundColor(.primary)
        .widgetURL(URL(string: "memora://recording"))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Image(systemName: "waveform")
            .foregroundStyle(.red)
        }
        DynamicIslandExpandedRegion(.center) {
          Text(context.attributes.title)
            .font(.headline)
            .lineLimit(1)
        }
        DynamicIslandExpandedRegion(.trailing) {
          elapsedText(context.state)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text(context.state.isPaused ? "一時停止中" : "このiPhoneに安全に保存しています")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } compactLeading: {
        Image(systemName: "waveform")
          .foregroundStyle(.red)
      } compactTrailing: {
        elapsedText(context.state)
          .font(.caption2.monospacedDigit())
          .frame(width: 42)
      } minimal: {
        Image(systemName: "waveform")
          .foregroundStyle(.red)
      }
      .keylineTint(.primary)
      .widgetURL(URL(string: "memora://recording"))
    }
    .supplementalActivityFamilies([.small, .medium])
  }
}

private struct MemoraLiveActivityView: View {
  @Environment(\.activityFamily) private var activityFamily
  var context: ActivityViewContext<MemoraRecordingAttributes>

  var body: some View {
    if activityFamily == .small {
      HStack {
        Image(systemName: context.state.isPaused ? "pause.fill" : "waveform")
          .foregroundStyle(.red)
        elapsedText(context.state)
          .font(.headline.monospacedDigit())
      }
      .padding()
    } else {
      HStack(spacing: 14) {
        Image(systemName: context.state.isPaused ? "pause.fill" : "waveform")
          .font(.title2.weight(.semibold))
          .foregroundStyle(.red)

        VStack(alignment: .leading, spacing: 2) {
          Text(context.attributes.title)
            .font(.headline)
            .lineLimit(1)
          Text(context.state.isPaused ? "一時停止中 · 端末に保存" : "録音中 · 端末に保存")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        elapsedText(context.state)
          .font(.title3.monospacedDigit().weight(.medium))
      }
      .padding()
    }
  }
}

/// A live timer while recording; the frozen elapsed time while paused, so the
/// number never keeps counting during a pause.
@ViewBuilder
private func elapsedText(_ state: MemoraRecordingAttributes.ContentState) -> some View {
  if state.isPaused {
    Text(formatElapsed(state.pausedElapsed))
  } else {
    Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false)
  }
}

private func formatElapsed(_ interval: TimeInterval) -> String {
  let total = max(0, Int(interval))
  let hours = total / 3_600
  let minutes = (total % 3_600) / 60
  let seconds = total % 60
  if hours > 0 {
    return String(format: "%d:%02d:%02d", hours, minutes, seconds)
  }
  return String(format: "%02d:%02d", minutes, seconds)
}
