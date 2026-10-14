import AppIntents

struct MemoraProjectEntity: AppEntity {
  var id: UUID
  var name: String
  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "プロジェクト")
  static var defaultQuery = MemoraProjectEntityQuery()
  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}
