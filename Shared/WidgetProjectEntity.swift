import AppIntents

struct WidgetProjectEntity: AppEntity {
  var id: UUID
  var name: String
  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "プロジェクト")
  static var defaultQuery = WidgetProjectEntityQuery()
  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}
