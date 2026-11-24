import Foundation

/// One photo kept by a record in a project, named by the file the record holds.
struct ProjectPhoto: Identifiable, Hashable {
  var name: String
  var date: Date
  var recordID: UUID
  var recordTitle: String

  var id: String { name }
}
