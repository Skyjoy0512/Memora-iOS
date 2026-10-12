import SwiftUI

struct ProjectWorkspaceRow: View {
  var item: ProjectWorkspaceItem
  @State private var movingMeeting: Meeting?

  var body: some View {
    NavigationLink(value: item.route) {
      switch item {
      case .source(let value): ProjectSourceRow(source: value)
      case .recording(let value): ProjectRecordRow(meeting: value)
      case .document(let value): ProjectDocumentRow(document: value)
      }
    }
    .buttonStyle(.plain)
    .contextMenu {
      if case .recording(let meeting) = item {
        Button("プロジェクトへ移動", icon: .folder) { movingMeeting = meeting }
      }
    }
    .sheet(item: $movingMeeting) { meeting in
      BulkSpacePickerSheet(meetingIDs: [meeting.id], onMove: {})
    }
  }
}
