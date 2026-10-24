import Foundation

struct MeetingSummaryPosterSection: Equatable, Identifiable {
  var id: Int
  var headings: [String]
  var groups: [Group] = []

  struct Group: Equatable, Identifiable {
    var id: Int
    var lines: [Line]
  }

  struct Line: Equatable, Identifiable {
    var id: Int
    var depth: Int
    var prefix: String
    var text: String
  }
}
