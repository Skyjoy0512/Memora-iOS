import Foundation

/// Transport completion, evidence eligibility and persistence are separate gates.
/// Matching a quote proves provenance, not semantic entailment of free prose.
struct SummaryPartArtifact: Codable {
  /// Integration has its own bound; the planner additionally enforces the
  /// selected model's context. A cache limit must not truncate valid analysis.
  static let maximumIntegrationBytes = 4 * 1_024 * 1_024
  var notes: String
  var sourceReferences: [Reference]

  func validated(in index: SummarySourceIndex, part: [String], compact: Bool) -> Bool {
    guard !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          notes.utf8.count <= Self.maximumIntegrationBytes,
          !sourceReferences.isEmpty, sourceReferences.count <= 256 else { return false }
    return sourceReferences.allSatisfy { reference in
      guard let id = index.originalID(for: reference.sourceSegmentID, allowShortIDs: compact),
            let entry = index.entries.first(where: { $0.segment.id == id }) else { return false }
      let marker = compact ? "] \(entry.shortID) \(entry.speakerAlias): " : "] [segmentID=\(id.uuidString)] "
      return index.validates(id: reference.sourceSegmentID, quote: reference.quote, allowShortIDs: compact) &&
        part.contains { line in
          guard line.hasPrefix("["), let end = line.firstIndex(of: "]"),
                line[end...].hasPrefix(marker) else { return false }
          let content = line.index(end, offsetBy: marker.count)
          return line[content...].contains(reference.quote)
        }
    }
  }

  enum Acceptance {
    case structured(SummaryPartArtifact)
    case legacy(String)
    case rejected
  }

  /// A declared JSON response cannot fall through to the legacy prose route.
  /// Invalid references reject the whole note: an undifferentiated notes string
  /// cannot safely be repaired by deleting one reference and keeping its claims.
  static func acceptance(_ text: String, in index: SummarySourceIndex,
                         part: [String], compact: Bool) -> Acceptance {
    let payload = jsonPayload(text)
    guard !payload.isEmpty, text.utf8.count <= Self.maximumIntegrationBytes else { return .rejected }
    if let artifact = decode(text) {
      return artifact.validated(in: index, part: part, compact: compact) ? .structured(artifact) : .rejected
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if payload.hasPrefix("{") || payload.hasPrefix("[") || trimmed.hasPrefix("```json") ||
        payload.contains("\"sourceReferences\"") || payload.contains("\"notes\":") {
      return .rejected
    }
    return .legacy(text)
  }

  static func decode(_ text: String) -> Self? {
    guard text.utf8.count <= Self.maximumIntegrationBytes else { return nil }
    return try? JSONDecoder().decode(Self.self, from: Data(jsonPayload(text).utf8))
  }

  static func hasMalformedStructuredNotes(_ text: String) -> Bool {
    let payload = jsonPayload(text)
    guard payload.hasPrefix("{"), payload.contains("\"notes\"") else { return false }
    return (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) == nil
  }

  private static func jsonPayload(_ text: String) -> String {
    var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let newline = value.firstIndex(where: \.isNewline) {
      let first = value[..<newline].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      if first == "```json" || first == "```" {
        value = String(value[value.index(after: newline)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix("```") { value = String(value.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines) }
      }
    }
    return value
  }

  struct Reference: Codable {
    var sourceSegmentID: String
    var quote: String
  }
}
