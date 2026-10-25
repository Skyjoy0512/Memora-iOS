import Foundation

/// A separate interpretation, with source quotations retained for inspection.
struct MeetingInfographic: Codable, Equatable {
  var version = 1
  var meetingID: UUID
  var sourceSummary: String
  var privacy: RecordPrivacy
  var modelLabel: String
  var generatedAt: Date
  var content: Content

  struct Claim: Codable, Equatable, Identifiable {
    var label: String
    var text: String
    var evidence: String
    var id: String { label }
  }

  struct Panel: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case metric, flow, comparison, timeline, note }
    var title: String
    var kind: Kind
    var items: [Claim]
    var id: String { title }
  }

  struct Content: Codable, Equatable {
    var headline: Claim
    var panels: [Panel]
    var questions: [String]

    func validate(against summary: String) throws {
      guard (1...4).contains(panels.count), questions.count == 3,
            Set(questions).count == 3, Set(panels.map(\.title)).count == panels.count,
            questions.allSatisfy({ Self.bounded($0, 90) }) else { throw ValidationError.invalid }
      let source = Self.normalized(summary)
      try Self.validate(headline, source: source, limit: 64)
      for panel in panels {
        guard Self.bounded(panel.title, 24), (1...2).contains(panel.items.count),
              Set(panel.items.map(\.label)).count == panel.items.count,
              GroundedQuantity.supports(panel.title, in: panel.items.map(\.evidence).joined(separator: " ")),
              GroundedQuantity.preservesQualification(panel.title, in: panel.items.map(\.evidence).joined(separator: " "), considersEvidence: false) else { throw ValidationError.invalid }
        for item in panel.items { try Self.validate(item, source: source, limit: 48) }
      }
    }

    private static func validate(_ claim: Claim, source: String, limit: Int) throws {
      let quote = normalized(claim.evidence)
      guard bounded(claim.label, 24), bounded(claim.text, limit), bounded(claim.evidence, 800, allowsNewlines: true),
            quote.count >= 4, source.contains(quote),
            GroundedQuantity.supports(claim.label + " " + claim.text, in: quote),
            GroundedQuantity.preservesQualification(claim.text, in: quote),
            GroundedQuantity.preservesQualification(claim.label, in: quote, considersEvidence: false) else { throw ValidationError.invalid }
    }

    private static func bounded(_ text: String, _ limit: Int, allowsNewlines: Bool = false) -> Bool {
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= limit
        && (allowsNewlines || !text.contains(where: \.isNewline))
        && !text.unicodeScalars.contains { CharacterSet.controlCharacters.subtracting(.newlines).contains($0) }
    }

    private static func normalized(_ text: String) -> String {
      text.replacingOccurrences(of: "**", with: "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

  }

  enum ValidationError: LocalizedError {
    case invalid
    var errorDescription: String? { "図解の構造または本文の根拠を確認できませんでした。本文は変更していません。もう一度生成してください。" }
  }

  static func decode(_ json: String?, meetingID: UUID, summary: String, privacy: RecordPrivacy) -> Self? {
    guard let json, json.utf8.count <= 200_000, let data = json.data(using: .utf8),
          let result = try? JSONDecoder().decode(Self.self, from: data), result.version == 1,
          result.meetingID == meetingID, result.sourceSummary == summary, result.privacy == privacy,
          (try? result.content.validate(against: summary)) != nil else { return nil }
    return result
  }
}
