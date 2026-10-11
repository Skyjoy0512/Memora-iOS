import Foundation

struct JournalHealthRequest: Hashable {
  var period: ReviewPeriod
  var enabled: Bool
  var teamID: String?
  var isActive: Bool
  var isReviewPresented: Bool
  var refreshID = 0

  var canRead: Bool { enabled && teamID == nil && isActive && !isReviewPresented }
}
