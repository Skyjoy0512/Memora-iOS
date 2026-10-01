import SwiftUI

struct MeetingRow: View {
  var meeting: Meeting
  /// `List` adds its own indicator for a `NavigationLink`, so rows inside one
  /// should turn this off.
  var showsDisclosure = true
  /// A teammate's name when the record is theirs, shown under the title.
  var sharedBy: String?

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      MemoraIconBadge(symbol: meeting.source == .recording ? .waveform : .squareAndArrowDown)

      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(meeting.title)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(2)

          if SampleContent.isSample(meetingID: meeting.id) {
            SampleTag()
          }
        }

        if let sharedBy {
          SharedOwnerBadge(ownerName: sharedBy)
        }

        if showsSummary {
          Text(meeting.shortSummaryPreview)
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
        Image(icon: .chevronRight)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.primary)
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
    if let sharedBy {
      parts.append("\(sharedBy)さんが共有")
    }
    if SampleContent.isSample(meetingID: meeting.id) {
      parts.append("サンプル")
    }
    if showsSummary {
      parts.append(meeting.summaryPreview)
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
