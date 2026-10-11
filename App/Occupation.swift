import Foundation

struct Occupation: Identifiable, Codable, Hashable {
  var id: String
  var categoryID: String
  var title: String
  var description: String
  var recommendedTemplateIDs: [String]
  var recommendedUseCaseIDs: [String]
}
