import SwiftUI

struct LibraryDestinationView: View {
  var route: LibraryRoute

  var body: some View {
    switch route {
    case .meeting(let id): MeetingDetailView(meetingID: id)
    case .transcript(let id): TranscriptView(meetingID: id)
    case .space(let id): SpaceDetailView(spaceID: id)
    case .tasks: TasksView()
    case .allMeetings: AllMeetingsView()
    case .settings: SettingsView()
    case .stateGallery: StateGalleryView()
    case .documents: DocumentsView()
    case .document(let id): DocumentDetailView(documentID: id)
    case .people: PeopleView()
    case .person(let id): PersonDetailView(personID: id)
    case .sharedRecord(let id): SharedRecordView(recordID: id)
    case .sharedProject(let id): SharedProjectView(projectID: id)
    }
  }
}
