import Foundation

extension ArtifactSourceTarget {
  static func presentationSourceID(_ value: String) -> Self? {
    let parts = value.split(separator: ":", maxSplits: 1)
    guard parts.count == 2, let id = UUID(uuidString: String(parts[1])) else { return nil }
    switch parts[0] {
    case "record", "transcript", "summary": return .record(.meeting(id))
    case "task": return .record(.task(id))
    case "person": return .record(.person(id))
    case "journal": return .record(.journal(id))
    default: return nil
    }
  }
}
