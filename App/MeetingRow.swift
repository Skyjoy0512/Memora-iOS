import SwiftUI

struct MeetingRow: View {
  var meeting: Meeting
  /// `List` adds its own indicator for a `NavigationLink`, so rows inside one
  /// should turn this off.
  var showsDisclosure = true

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      MemoraIconBadge(symbol: meeting.source == .recording ? "waveform" : "square.and.arrow.down")

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

      if showsDisclosure {
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.tertiary)
          .padding(.top, 4)
          .accessibilityHidden(true)
      }
    }
    .padding(.vertical, 12)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
  }

  /// One sentence for VoiceOver instead of the pieces read in view order.
  private var accessibilityLabel: String {
    var parts = [meeting.displayTitle]
    if showsSummary {
      parts.append(meeting.summary)
    }
    parts.append(MemoraFormat.relativeDate(meeting.createdAt))
    parts.append(MemoraFormat.duration(meeting.duration))
    parts.append(meeting.status.shortLabel)
    return parts.joined(separator: "、")
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
