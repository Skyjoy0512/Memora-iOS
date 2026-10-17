import Foundation

/// One resolved row of the SourceList.
///
/// The name comes from the stored record, not from the model's JSON, so a
/// citation cannot rename a record. `supplement` is optional model text shown
/// beneath the name; `excerptCount` is the number of stored excerpts the
/// answer actually read, so it is grounded metadata rather than a claim.
struct AIInterfaceSourceRow: Equatable, Identifiable {
  var id: UUID
  var title: String
  var supplement: String?
  var excerptCount: Int
  /// Whether the record still exists and is currently permitted to open.
  var isAvailable: Bool
}
