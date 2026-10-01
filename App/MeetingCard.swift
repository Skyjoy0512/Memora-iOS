import SwiftUI

/// A large, gradient-filled gallery tile for one audio file. Tapping it opens
/// the meeting with a zoom transition.
struct MeetingCard: View {
  @Environment(\.colorScheme) private var colorScheme
  var meeting: Meeting
  /// True while several cards are being chosen, so each shows a selection mark.
  var isSelecting = false
  var isSelected = false
  /// A teammate's name when the record is theirs; it takes the status's place
  /// so the card says at a glance whose it is.
  var sharedBy: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 8) {
        badge

        if SampleContent.isSample(meetingID: meeting.id) {
          SampleTag()
        }

        Spacer(minLength: 8)

        if let sharedBy {
          SharedOwnerBadge(ownerName: sharedBy)
        } else {
          MeetingStatusLabel(status: meeting.status)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
        }
      }

      Spacer(minLength: 28)

      Text(meeting.title)
        .font(.title2.bold())
        .foregroundStyle(.primary)
        .lineLimit(2)

      Text(subtitle)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .padding(.top, 4)

      HStack(spacing: 5) {
        Image(icon: .calendar)
        Text(recordingDate)
      }
      .font(.caption.weight(.medium))
      .foregroundStyle(.primary)
      .padding(.top, 10)
    }
    .padding(18)
    .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 26, style: .continuous)
        .fill(
          LinearGradient(
            colors: [Color.primary.opacity(0.075), Color.primary.opacity(0.025)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
    }
    .overlay {
      RoundedRectangle(cornerRadius: 26, style: .continuous)
        .stroke(
          isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.06)),
          lineWidth: isSelected ? 2 : 0.5
        )
    }
    .overlay(alignment: .bottomTrailing) {
      if isSelecting {
        // The icons are single-layer, so the white behind the check is drawn
        // separately rather than as a second palette color.
        Image(icon: isSelected ? .checkmarkCircleFill : .circle)
          .font(.title2)
          .foregroundStyle(.primary)
          .background {
            if isSelected {
              Circle().fill(.white).padding(4)
            }
          }
          .padding(16)
          .accessibilityHidden(true)
      }
    }
    .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.06), radius: 16, y: 8)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }

  private var recordingDate: String {
    meeting.createdAt.formatted(.dateTime.month().day().hour().minute())
  }

  private var accessibilityLabel: String {
    var parts = [meeting.title]
    if let sharedBy {
      parts.append("\(sharedBy)さんが共有")
    }
    if SampleContent.isSample(meetingID: meeting.id) {
      parts.append("サンプル")
    }
    parts.append(recordingDate)
    parts.append(MemoraFormat.duration(meeting.duration))
    parts.append(meeting.status.shortLabel)
    return parts.joined(separator: "、")
  }

  private var badge: some View {
    HStack(spacing: 6) {
      Image(icon: meeting.source == .recording ? .waveform : .squareAndArrowDown)
      Text(MemoraFormat.duration(meeting.duration))
    }
    .font(.caption.weight(.semibold))
    .foregroundStyle(.primary)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(.thinMaterial, in: Capsule())
  }

  private var subtitle: String {
    switch meeting.status {
    case .ready, .partialFailure:
      meeting.summary.isEmpty ? meeting.status.shortLabel : meeting.shortSummaryPreview
    default:
      meeting.status.shortLabel
    }
  }

}
