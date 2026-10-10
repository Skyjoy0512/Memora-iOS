import Foundation

struct JournalHealthRequest: Hashable {
  var period: ReviewPeriod
  var enabled: Bool
  var teamID: String?
  var isActive: Bool
  var isReviewPresented: Bool

  var canRead: Bool { enabled && teamID == nil && isActive && !isReviewPresented }
}
