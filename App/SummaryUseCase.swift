import Foundation

struct SummaryUseCase: Identifiable, Codable, Hashable {
  var id: String
  var title: String
  var description: String
  var templateIDs: [String]
}
