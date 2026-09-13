import SwiftUI

struct MeetingRow: View {
  var meeting: Meeting

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: meeting.source == .recording ? "waveform" : "arrow.down.doc")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .frame(width: 36, height: 36)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

      VStack(alignment: .leading, spacing: 6) {
        Text(meeting.title)
          .font(.body.weight(.semibold))
          .foregroundStyle(.primary)
          .lineLimit(2)

        if showsSummary {
          Text(meeting.summary)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .lineSpacing(2)
        }

        HStack(spacing: 6) {
          Text(MemoraFormat.relativeDate(meeting.createdAt))
          Text("·")
          Text(MemoraFormat.duration(meeting.duration))
          Text("·")
          MeetingStatusLabel(status: meeting.status)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Spacer(minLength: 8)

      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.tertiary)
        .padding(.top, 4)
    }
    .padding(.vertical, 12)
    .contentShape(Rectangle())
  }

  private var showsSummary: Bool {
    switch meeting.status {
    case .ready, .partialFailure:
      return !meeting.summary.isEmpty
    default:
      return false
    }
  }
}
