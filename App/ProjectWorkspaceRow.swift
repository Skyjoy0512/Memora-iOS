import SwiftUI

struct ProjectWorkspaceRow: View {
  var item: ProjectWorkspaceItem
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var zoom
  @State private var movingMeeting: Meeting?

  var body: some View {
    NavigationLink {
      if reduceMotion {
        LibraryDestinationView(route: item.route)
      } else {
        LibraryDestinationView(route: item.route)
          .navigationTransition(.zoom(sourceID: item.id, in: zoom))
      }
    } label: {
      rowContent
        .matchedTransitionSource(id: item.id, in: zoom)
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

  @ViewBuilder private var rowContent: some View {
    switch item {
    case .source(let value): ProjectSourceRow(source: value)
    case .recording(let value): ProjectRecordRow(meeting: value)
    case .document(let value): ProjectDocumentRow(document: value)
    }
  }
}
