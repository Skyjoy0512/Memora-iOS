import Foundation

struct WebResearchReport: Identifiable, Codable, Hashable, Sendable {
  var id = UUID()
  var query: String
  var mode: Mode
  var queries: [String]
  var sources: [WebResearchSource] = []
  var attemptedQueries: [String]?
  var completedQueries: [String]?
  var answer = ""
  var citedSourceIDs: [UUID] = []
  var sentSourceIDs: [UUID]?
  var isChatSearch: Bool?
  var engineLabel: String?
  var modelLabel: String?
  var status: Status = .searching
  var error: String?
  var createdAt = Date.now
  var workspaceID: String?
  var progressEvents: [String]?
  var coverageGaps: [String]?
  var modelCalls: Int?
  var savedProjectID: UUID?
  var savedNoteID: UUID?
  var savedSourceIDs: [UUID] = []
  enum Mode: String, Codable, CaseIterable, Sendable {
    case search, deepResearch
    var label: String { self == .search ? "Web検索" : "Deep Research" }
  }
  enum Status: String, Codable, Sendable { case searching, writing, complete, failed, interrupted }
}
