import Foundation

struct CompanyTemplate: Identifiable, Codable, Hashable {
  enum Format: String, Codable { case docx, pptx }
  var id = UUID()
  var name: String
  var format: Format
  var fileReference: String
  var projectID: UUID?
  var workspaceID: String?
  var createdAt = Date.now
  var updatedAt = Date.now
  var version = 1
  var brand: [String: String] = [:]
  var analysis: CompanyTemplateEngine.Analysis
  var allowedUsers = ["local-owner"]
}
