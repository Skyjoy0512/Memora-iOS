import SwiftUI

struct AllMeetingsView: View {
  @Environment(MemoraModel.self) private var model
  @State private var query = ""

  var body: some View {
    List {
      ForEach(filteredMeetings) { meeting in
        NavigationLink(value: LibraryRoute.meeting(meeting.id)) {
          MeetingRow(meeting: meeting)
        }
        .swipeActions(edge: .trailing) {
          Button("削除", systemImage: "trash", role: .destructive) {
            model.deleteMeeting(meeting.id)
          }
        }
      }
    }
    .listStyle(.plain)
    .navigationTitle("すべての会話")
    .searchable(text: $query, prompt: "タイトル、発言、決定、タスク")
    .overlay {
      if filteredMeetings.isEmpty {
        ContentUnavailableView.search(text: query)
      }
    }
  }

  private var filteredMeetings: [Meeting] {
    guard !query.isEmpty else { return model.meetings }
    return model.meetings.filter { meeting in
      meeting.title.localizedCaseInsensitiveContains(query)
        || meeting.summary.localizedCaseInsensitiveContains(query)
        || meeting.transcript.contains { $0.text.localizedCaseInsensitiveContains(query) }
    }
  }
}
