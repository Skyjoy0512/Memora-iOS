import AppIntents

struct MemoraProjectEntityQuery: EntityStringQuery {
  @Dependency private var model: MemoraModel

  @MainActor private func available() -> [MemoraProjectEntity] {
    guard UserDefaults.standard.bool(forKey: "memora.shortcuts.projectNames"), !AppLockService.isEnabled,
          !model.isStoreProtected, !model.isRestoring, model.currentTeamID == nil else { return [] }
    return model.spaces.prefix(100).map { .init(id: $0.id, name: String($0.name.prefix(80))) }
  }

  @MainActor func entities(for identifiers: [UUID]) async throws -> [MemoraProjectEntity] {
    let ids = Set(identifiers.prefix(100))
    return available().filter { ids.contains($0.id) }
  }

  @MainActor func suggestedEntities() async throws -> [MemoraProjectEntity] { available() }
  @MainActor func entities(matching string: String) async throws -> [MemoraProjectEntity] {
    available().filter { $0.name.localizedStandardContains(string) }
  }
}
