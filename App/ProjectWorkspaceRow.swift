import SwiftUI

struct ProjectWorkspaceRow: View {
  var item: ProjectWorkspaceItem
  var zoomNamespace: Namespace.ID?
  @State private var movingMeeting: Meeting?

  var body: some View {
    NavigationLink(value: item.route) {
      if let zoomNamespace, let transitionID {
        rowContent.matchedTransitionSource(id: transitionID, in: zoomNamespace)
      } else {
        rowContent
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

  private var transitionID: UUID? {
    switch item {
    case .source(let value): value.id
    case .recording(let value): value.id
    case .document: nil
    }
  }

  @ViewBuilder private var rowContent: some View {
    switch item {
    case .source(let value): ProjectSourceRow(source: value)
    case .recording(let value): LibraryRecordRow(meeting: value, showsPreview: true)
    case .document(let value): ProjectDocumentRow(document: value)
    }
  }
}
