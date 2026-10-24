import SwiftUI

struct MeetingSummaryPosterEntry: View {
  @Environment(MemoraModel.self) private var model
  var meetingID: UUID
  @State private var snapshot: MeetingSummaryPosterSnapshot?

  var body: some View {
    Button {
      snapshot = MeetingSummaryPosterSnapshot(meetingID: meetingID, model: model)
    } label: {
      HStack(spacing: 12) {
        Image(icon: .photo, size: 24)
        VStack(alignment: .leading, spacing: 4) {
          Text("1枚サマリー").font(.headline)
          Text("要旨・決定・次のアクションを画像に").font(.caption).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        Image(icon: .chevronRight, size: 16).accessibilityHidden(true)
      }
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("summary.poster.open")
    .accessibilityHint("端末内でPNGを作成します。本文は変更しません")
    .sheet(item: $snapshot) { MeetingSummaryPosterSheet(snapshot: $0) }
  }
}
