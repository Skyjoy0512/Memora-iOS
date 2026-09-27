import Foundation
import SwiftUI

struct UpcomingMeeting: Identifiable, Hashable {
  var id: String
  var title: String
  var start: Date
  var end: Date
}
