import SwiftUI

struct MeetingRow: View {
  var meeting: Meeting

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: meeting.source == .recording ? "waveform" : "arrow.down.doc")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.indigo)
        .frame(width: 40, height: 40)
        .background(.indigo.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

      VStack(alignment: .leading, spacing: 6) {
        Text(meeting.title)
          .font(.body.weight(.semibold))
          .foregroundStyle(.primary)
          .lineLimit(2)

        HStack(spacing: 6) {
          Text(MemoraFormat.relativeDate(meeting.createdAt))
          Text("·")
          Text(MemoraFormat.duration(meeting.duration))
        }
        .font(.caption)
        .foregroundStyle(.secondary)

        MeetingStatusLabel(status: meeting.status)
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
}
