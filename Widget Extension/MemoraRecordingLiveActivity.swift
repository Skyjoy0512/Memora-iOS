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
          Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text("このiPhoneに安全に保存しています")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } compactLeading: {
        Image(systemName: "waveform")
          .foregroundStyle(.red)
      } compactTrailing: {
        Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
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
        Image(systemName: "waveform")
          .foregroundStyle(.red)
        Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
          .font(.headline.monospacedDigit())
      }
      .padding()
    } else {
      HStack(spacing: 14) {
        Image(systemName: "waveform")
          .font(.title2.weight(.semibold))
          .foregroundStyle(.red)

        VStack(alignment: .leading, spacing: 2) {
          Text(context.attributes.title)
            .font(.headline)
            .lineLimit(1)
          Text("録音中 · 端末に保存")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
          .font(.title3.monospacedDigit().weight(.medium))
      }
      .padding()
    }
  }
}
