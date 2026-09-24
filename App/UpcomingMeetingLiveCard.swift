import SwiftUI

/// The next calendar event drawn like a Live Activity — a dark, rounded card
/// with a live countdown and its own action row. It is not a real Live Activity;
/// it only borrows the look.
struct UpcomingMeetingLiveCard: View {
  var meeting: UpcomingMeeting
  var isStarting: Bool
  var onStart: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "waveform")
          .font(.title3.weight(.semibold))
          .foregroundStyle(.white)
          .frame(width: 42, height: 42)
          .background(.white.opacity(0.16), in: Circle())

        VStack(alignment: .leading, spacing: 3) {
          Text("次の会議")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.65))

          Text(meeting.title)
            .font(.headline)
            .foregroundStyle(.white)
            .lineLimit(2)

          Text(timeRange)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.75))
        }

        Spacer(minLength: 8)

        VStack(alignment: .trailing, spacing: 2) {
          Text(isUpcoming ? "開始まで" : "開始時刻")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.65))

          Text(meeting.start, style: .timer)
            .font(.title3.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
        }
      }
      .padding(16)

      Divider().overlay(.white.opacity(0.12))

      Button(action: onStart) {
        Label("録音を開始", systemImage: "waveform")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.black)
          .frame(maxWidth: .infinity, minHeight: 44)
          .background(.white, in: Capsule())
          .contentShape(Capsule())
      }
      .buttonStyle(.plain)
      .disabled(isStarting)
      .opacity(isStarting ? 0.6 : 1)
      .padding(12)
    }
    .background(
      LinearGradient(
        colors: [Color(white: 0.17), Color(white: 0.07)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      ),
      in: RoundedRectangle(cornerRadius: 26, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 26, style: .continuous)
        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
    )
    .accessibilityElement(children: .contain)
  }

  private var isUpcoming: Bool {
    meeting.start > .now
  }

  private var timeRange: String {
    let start = meeting.start.formatted(date: .omitted, time: .shortened)
    let end = meeting.end.formatted(date: .omitted, time: .shortened)
    return "\(start)〜\(end)"
  }
}
