import Foundation

/// Run against an isolated preferences suite; no API calls or user data.
@main
struct RegisteredLLMStoreChecks {
  @MainActor
  static func main() {
    let suite = "memora.registered-model-checks.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    defaults.set("existing-model", forKey: "memora.aiModel.moonshot")
    let store = RegisteredLLMStore(defaults: defaults)
    precondition(store.selectedID == nil, "First launch must use Auto")
    precondition(store.models.count == 1 && store.models[0].modelID == "existing-model")
    let migratedID = store.models[0].id
    precondition(RegisteredLLMStore(defaults: defaults).models[0].id == migratedID)

    let fast = RegisteredLLM(provider: .deepSeek, modelID: " fast-model\n", name: " 日常用 ")
    let careful = RegisteredLLM(provider: .deepSeek, modelID: "careful-model", name: "詳しく考える")
    precondition(store.save(fast) && store.save(careful))
    precondition(store.models.count == 3, "Multiple models from one provider must survive")
    store.select(fast.id)
    let reopened = RegisteredLLMStore(defaults: defaults)
    precondition(reopened.selectedModel?.name == "日常用")
    precondition(reopened.selectedModel?.selection.modelID == "fast-model")
    precondition(reopened.selectedModel?.selection.provider == .deepSeek)
    precondition(reopened.selectedModel?.selection.modelLabel == "DeepSeek · 日常用")

    precondition(!store.save(RegisteredLLM(provider: .deepSeek, modelID: "fast-model", name: "重複")))
    precondition(!store.save(RegisteredLLM(provider: .openAI, modelID: " \n", name: "空")))
    var renamed = store.selectedModel!
    renamed.name = "新しい名前"
    precondition(store.save(renamed))
    precondition(store.selectedID == fast.id && store.selectedModel?.name == "新しい名前")

    store.select(nil)
    precondition(RegisteredLLMStore(defaults: defaults).selectedModel == nil)
    store.select(careful.id)
    store.remove(careful.id)
    precondition(store.selectedID == nil, "Removing the active model must return to Auto")
    let final = RegisteredLLMStore(defaults: defaults)
    precondition(final.selectedID == nil && final.models.count == 2)
    final.remove(migratedID)
    precondition(!RegisteredLLMStore(defaults: defaults).models.contains { $0.id == migratedID },
                 "Removed legacy choices must not reappear")
    final.select(UUID())
    precondition(final.selectedID == nil, "Unknown selection must resolve to Auto")
    print("PASS: migration, multiple models, persistence, routing identity, rename, validation, Auto, removal")
  }
}
