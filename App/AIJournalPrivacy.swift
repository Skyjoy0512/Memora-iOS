import Foundation

enum AIJournalPrivacy {
  static func allowsReading(kind: LifeLogKind, origin: LifeLogOrigin) -> Bool {
    kind != .location && origin == .manual
  }
}
