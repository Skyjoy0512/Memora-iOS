import SwiftUI

/// The half-height sheet that asks how to record a coming event. An event with
/// a meeting link offers the web recording first.
struct RecordingMethodSheet: View {
  var meeting: UpcomingMeeting
  var onChoose: (RecordingMethod) -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 4) {
          Text("\(UpcomingMeetingFormat.day(meeting.start)) \(UpcomingMeetingFormat.timeRange(meeting))")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(meeting.calendarColor ?? .accentColor)
          Text(meeting.title)
            .font(.title2.bold())
            .lineLimit(2)
        }

        VStack(spacing: 10) {
          ForEach(methods) { method in
            Button {
              onChoose(method)
            } label: {
              row(for: method)
            }
            .buttonStyle(.plain)
          }
        }

        Spacer(minLength: 0)
      }
      .padding(.horizontal, 20)
      .padding(.top, 4)
      .navigationTitle("録音方法")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
        }
      }
    }
    .presentationDetents([.medium])
    .presentationDragIndicator(.visible)
  }

  private var methods: [RecordingMethod] {
    meeting.isOnline ? [.online, .inPerson] : [.inPerson, .online]
  }

  private func row(for method: RecordingMethod) -> some View {
    HStack(spacing: 14) {
      Image(icon: method.icon)
        .font(.title3.weight(.semibold))
        .foregroundStyle(.tint)
        .frame(width: 44, height: 44)
        .background(Color.accentColor.opacity(0.12), in: Circle())

      VStack(alignment: .leading, spacing: 2) {
        Text(method.title)
          .font(.body.weight(.semibold))
          .foregroundStyle(.primary)
        Text(method.detail)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 8)

      Image(icon: .chevronRight)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.tertiary)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .memoraCard(radius: 18)
    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
}
