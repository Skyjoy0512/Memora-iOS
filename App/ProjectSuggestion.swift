import Foundation

/// A project a record might belong in, with the evidence for it. The signal is
/// counted from that evidence only — the same calendar series, the same
/// meeting name, the same people — never guessed.
struct ProjectSuggestion: Identifiable, Hashable {
  var space: MemoraSpace
  /// 3 strong, 2 worth a look; weaker suggestions are not offered.
  var signal: Int
  var reasons: [String]

  var id: UUID { space.id }

  var label: String {
    signal >= 3 ? "根拠が強い" : "確認が必要"
  }
}
