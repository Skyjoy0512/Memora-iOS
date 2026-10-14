import AppIntents

struct WidgetProjectEntityQuery: EntityQuery {
  func defaultResult() async -> WidgetProjectEntity? {
    MemoraWidgetSnapshotStore.read()?.projects.first.map { .init(id: $0.id, name: $0.name) }
  }

  func entities(for identifiers: [UUID]) async throws -> [WidgetProjectEntity] {
    let ids = Set(identifiers.prefix(20))
    return (MemoraWidgetSnapshotStore.read()?.projects ?? []).filter { ids.contains($0.id) }.map { .init(id: $0.id, name: $0.name) }
  }

  func suggestedEntities() async throws -> [WidgetProjectEntity] {
    (MemoraWidgetSnapshotStore.read()?.projects ?? []).map { .init(id: $0.id, name: $0.name) }
  }
}
