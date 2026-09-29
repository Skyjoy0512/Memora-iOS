import Foundation
import SwiftUI

struct UpcomingMeeting: Identifiable, Hashable {
  var id: String
  var title: String
  var start: Date
  var end: Date
  /// The invitation carries a Zoom, Meet, Teams or Webex link, so the web
  /// meeting recording is offered first.
  var isOnline = false
}
