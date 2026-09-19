import Foundation

enum LibraryRoute: Hashable {
  case meeting(UUID)
  case transcript(UUID)
  case space(UUID)
  case allMeetings
  case settings
  case stateGallery
}
