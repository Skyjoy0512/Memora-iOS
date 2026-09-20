import SwiftUI

/// A large, gradient-filled gallery tile for one audio file. Tapping it opens
/// the meeting with a zoom transition.
struct MeetingCard: View {
  @Environment(\.colorScheme) private var colorScheme
  var meeting: Meeting

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 8) {
        badge

        Spacer(minLength: 8)

        MeetingStatusLabel(status: meeting.status)
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(.thinMaterial, in: Capsule())
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
        Image(systemName: "calendar")
        Text(recordingDate)
      }
      .font(.caption.weight(.medium))
      .foregroundStyle(.secondary)
      .padding(.top, 10)
    }
    .padding(18)
    .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
    .background {
      SeededGradient(seed: meeting.id)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
    .overlay {
      RoundedRectangle(cornerRadius: 26, style: .continuous)
        .stroke(.white.opacity(colorScheme == .dark ? 0.08 : 0.5), lineWidth: 0.5)
    }
    .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 18, y: 10)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(meeting.title)、\(recordingDate)、\(MemoraFormat.duration(meeting.duration))、\(meeting.status.shortLabel)")
  }

  private var recordingDate: String {
    meeting.createdAt.formatted(.dateTime.month().day().hour().minute())
  }

  private var badge: some View {
    HStack(spacing: 6) {
      Image(systemName: meeting.source == .recording ? "waveform" : "square.and.arrow.down")
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
      meeting.summary.isEmpty ? meeting.status.shortLabel : meeting.summary
    default:
      meeting.status.shortLabel
    }
  }

}
