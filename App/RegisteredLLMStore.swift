import Foundation
import Observation

@MainActor
@Observable
final class RegisteredLLMStore {
  private(set) var models: [RegisteredLLM]
  private(set) var selectedID: UUID?
  @ObservationIgnored private var defaults: UserDefaults
  private static let modelsKey = "memora.registeredLLMs"
  private static let selectionKey = "memora.askAI.registeredModel"

  var selectedModel: RegisteredLLM? {
    models.first { $0.id == selectedID }
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let data = defaults.data(forKey: Self.modelsKey) {
      models = (try? JSONDecoder().decode([RegisteredLLM].self, from: data)) ?? []
    } else {
      // Migrate explicit choices only; a provider's entire catalog is not a
      // list of models the person registered.
      models = LLMProvider.allCases.compactMap { provider in
        guard let id = defaults.string(forKey: "memora.aiModel.\(provider.rawValue)"),
              !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return RegisteredLLM(
          provider: provider, modelID: id,
          name: provider.suggestedModels.first { $0.id == id }?.name ?? id
        )
      }
      if let data = try? JSONEncoder().encode(models) {
        defaults.set(data, forKey: Self.modelsKey)
      }
    }
    let saved = defaults.string(forKey: Self.selectionKey).flatMap(UUID.init(uuidString:))
    selectedID = models.contains { $0.id == saved } ? saved : nil
  }

  func select(_ id: UUID?) {
    selectedID = models.contains { $0.id == id } ? id : nil
    defaults.set(selectedID?.uuidString, forKey: Self.selectionKey)
  }

  @discardableResult
  func save(_ model: RegisteredLLM) -> Bool {
    var cleaned = model
    cleaned.modelID = model.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
    cleaned.name = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.modelID.isEmpty else { return false }
    if cleaned.name.isEmpty { cleaned.name = cleaned.modelID }
    guard !models.contains(where: {
      $0.id != cleaned.id && $0.provider == cleaned.provider && $0.modelID == cleaned.modelID
    }) else { return false }
    if let index = models.firstIndex(where: { $0.id == cleaned.id }) {
      models[index] = cleaned
    } else {
      models.append(cleaned)
    }
    persist()
    return true
  }

  func register(provider: LLMProvider, modelID: String, name: String) {
    guard !models.contains(where: { $0.provider == provider && $0.modelID == modelID }) else { return }
    save(RegisteredLLM(provider: provider, modelID: modelID, name: name))
  }

  func remove(_ id: UUID) {
    models.removeAll { $0.id == id }
    if selectedID == id { select(nil) }
    persist()
  }

  private func persist() {
    guard let data = try? JSONEncoder().encode(models) else { return }
    defaults.set(data, forKey: Self.modelsKey)
  }
}
