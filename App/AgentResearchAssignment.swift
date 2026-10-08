import Foundation

struct AgentResearchAssignment: Sendable, Equatable {
  var role: String
  var request: String

  static func parse(_ objects: [[String: Any]]) -> [AgentResearchAssignment]? {
    guard (2...3).contains(objects.count) else { return nil }
    var assignments: [AgentResearchAssignment] = []
    for object in objects {
      guard let rawRole = object["role"] as? String,
            let rawRequest = object["request"] as? String else { return nil }
      let role = rawRole.trimmingCharacters(in: .whitespacesAndNewlines)
      let request = rawRequest.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !role.isEmpty, role.count <= 60, !request.isEmpty, request.count <= 2_000,
            !assignments.contains(where: { $0.role == role || $0.request == request }) else { return nil }
      assignments.append(AgentResearchAssignment(role: role, request: request))
    }
    return assignments
  }
}
