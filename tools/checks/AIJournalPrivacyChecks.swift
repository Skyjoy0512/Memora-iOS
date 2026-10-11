import Foundation

@main
struct AIJournalPrivacyChecks {
  static func main() {
    for kind in LifeLogKind.allCases {
      precondition(!AIJournalPrivacy.allowsReading(kind: kind, origin: .stationPass))
      precondition(!AIJournalPrivacy.allowsReading(kind: kind, origin: .visit))
      precondition(AIJournalPrivacy.allowsReading(kind: kind, origin: .manual) == (kind != .location))
    }
    print("AI journal privacy checks passed")
  }
}
