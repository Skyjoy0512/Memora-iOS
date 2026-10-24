import Foundation

/// A local, display-only relation. Construction requires the whole utterance,
/// so an omitted ending cannot turn a declined proposal into an agreement.
struct SummaryRelation: Hashable {
  var parent: String
  var target: Target
  var kind: Kind
  var sourceSegmentID: UUID
  var quote: String

  enum Target: Hashable { case point, decision }

  enum Kind: String {
    case reason, condition, effect

    var label: String {
      switch self {
      case .reason: "理由"
      case .condition: "条件"
      case .effect: "影響"
      }
    }

    var cues: [String] {
      switch self {
      case .reason: ["ため", "ので", "理由"]
      case .condition: ["場合", "なら", "条件"]
      case .effect: ["結果", "そのため", "よって", "影響"]
      }
    }
  }

  private init(parent: String, target: Target, kind: Kind, sourceSegmentID: UUID, quote: String) {
    self.parent = parent
    self.target = target
    self.kind = kind
    self.sourceSegmentID = sourceSegmentID
    self.quote = quote
  }

  /// Reuse the timestamps already sent to the small local model. Equal
  /// timestamps are ambiguous, never a reason to pick the first utterance.
  static func validated(parent: String, kind: String, sourceTime: String, quote: String,
                        points: [String], decisions: [String], transcript: [TranscriptSegment], duration: TimeInterval) -> Self? {
    let matches = transcript.filter {
      $0.timestamp.isFinite && $0.timestamp >= 0 && $0.timestamp < Double(Int.max)
        && MemoraFormat.duration($0.timestamp) == sourceTime
    }
    guard matches.count == 1, let source = matches.first else { return nil }
    let parent = parent.trimmingCharacters(in: .whitespacesAndNewlines)
    return validated(parent: parent, kind: kind, sourceSegmentID: source.id.uuidString, quote: quote,
      parents: points + decisions, target: points.contains(parent) ? .point : .decision, transcript: transcript, duration: duration)
  }

  static func validated(parent: String, kind: String, sourceSegmentID: String, quote: String,
                        parents: [String], target: Target = .decision, transcript: [TranscriptSegment], duration: TimeInterval) -> Self? {
    let parent = parent.trimmingCharacters(in: .whitespacesAndNewlines)
    let quote = quote.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (5...80).contains(parent.count), (8...200).contains(quote.count),
          !parent.contains(where: { $0.isNewline }), !quote.contains(where: { $0.isNewline }),
          parents.filter({ $0 == parent }).count == 1,
          let kind = Kind(rawValue: kind), let id = UUID(uuidString: sourceSegmentID),
          duration.isFinite, duration >= 0,
          transcript.filter({ $0.id == id }).count == 1,
          let source = transcript.first(where: { $0.id == id }),
          source.timestamp.isFinite, source.timestamp >= 0, source.timestamp <= duration,
          source.text.trimmingCharacters(in: .whitespacesAndNewlines) == quote,
          quote.contains(parent), kind.cues.contains(where: { quote.contains($0) }) else { return nil }
    return Self(parent: parent, target: target, kind: kind, sourceSegmentID: id, quote: quote)
  }

  static let generationInstructions = """
  relationsは、原文が明示した理由・条件・影響だけを最大2件。無ければ空配列。
  parentはpointsまたはdecisionsの1項目と完全一致させ、根拠の発言内の5〜80文字の節をそのまま使う。
  sourceTimeは提示された発言行の時刻（例00:12）。同じ時刻が複数あれば関係は出さない。quoteは発言の全文を200文字以内で逐語転記し、否定・留保・条件を切り取らない。全文が長ければ関係は出さない。
  kindはreason（ため・ので・理由）、condition（場合・なら・条件）、effect（結果・そのため・よって・影響）。親と関係が同じ発言で明示されない場合や単なる時系列は出さない。関係にするために決定や親の文を作らない。
  """
}
