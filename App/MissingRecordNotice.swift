import Foundation

/// Shown when a link points at a record this device does not have.
struct MissingRecordNotice: Identifiable {
  var id = UUID()
  var message: String
  /// True when the record is in the trash, so the alert can offer to open it.
  var offersTrash: Bool
}
