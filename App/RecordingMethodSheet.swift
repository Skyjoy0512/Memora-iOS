import SwiftUI

/// The half-height sheet that asks how to record a coming event. An event with
/// a meeting link offers the web recording first.
struct RecordingMethodSheet: View {
  var meeting: UpcomingMeeting
  var onChoose: (RecordingMethod) -> Void
  /// Opens an earlier record from the brief.
  var onOpenRecord: (UUID) -> Void = { _ in }

  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    // What earlier meetings of this series left open, gathered once.
    let brief = model.meetingBrief(for: meeting)

    NavigationStack {
      ScrollView {
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

          if let brief {
            MeetingBriefSection(brief: brief, onOpenRecord: onOpenRecord)
              .padding(.top, 8)
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 20)
      }
      .navigationTitle("録音方法")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
        }
      }
    }
    // With a brief to read, the sheet can be pulled up to full height.
    .presentationDetents(brief == nil ? [.medium] : [.medium, .large])
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
    .memoraCard()
    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
}
