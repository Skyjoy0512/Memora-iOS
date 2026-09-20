import SwiftUI

struct AllMeetingsView: View {
  @Environment(MemoraModel.self) private var model
  @State private var query = ""

  var body: some View {
    let meetings = filteredMeetings

    List {
      ForEach(meetings) { meeting in
        NavigationLink(value: LibraryRoute.meeting(meeting.id)) {
          MeetingRow(meeting: meeting, showsDisclosure: false)
        }
        .swipeActions(edge: .trailing) {
          Button("削除", systemImage: "trash", role: .destructive) {
            model.deleteMeeting(meeting.id)
          }
        }
      }
    }
    .listStyle(.plain)
    .animation(.smooth, value: meetings.map(\.id))
    .navigationTitle("すべての会話")
    .searchable(text: $query, prompt: "タイトル、発言、決定、タスク")
    .overlay {
      if meetings.isEmpty {
        ContentUnavailableView.search(text: query)
      }
    }
  }

  private var filteredMeetings: [Meeting] {
    guard !query.isEmpty else { return model.meetings }
    return model.meetings.filter {
      model.searchText(for: $0).localizedCaseInsensitiveContains(query)
    }
  }
}
