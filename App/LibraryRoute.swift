import Foundation

enum LibraryRoute: Hashable {
  case meeting(UUID)
  case meetingCitation(UUID, TimeInterval)
  case transcript(UUID)
  case space(UUID)
  case projectSources(UUID?)
  case projectSource(UUID)
  case projectPDF(UUID, Int)
  case projectChat(UUID)
  case projectChats(UUID?)
  case projectTasks(UUID)
  case tasks
  case allMeetings
  case settings
  case documents
  case document(UUID)
  case people
  case person(UUID)
  /// A teammate's shared record, by `SharedRecord.id`.
  case sharedRecord(String)
  /// A teammate's shared project, by `SharedProject.id`.
  case sharedProject(String)
}
