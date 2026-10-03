import Foundation

extension MemoraModel {
  /// Capture once per question so changing the menu cannot reroute an answer
  /// already in flight. Auto follows the explicit settings engine policy.
  var askAIConfiguration: (engine: AIEngine, llm: LLMSelection) {
    if let registered = registeredLLMs.selectedModel {
      return (.cloud, registered.selection)
    }
    return settingsAIConfiguration
  }

  /// The engine chosen in settings, as requests run it: Memora Intelligence
  /// is the cloud path pointed at Memora's server with Memora's token, so the
  /// engines downstream need no case of their own for it.
  var settingsAIConfiguration: (engine: AIEngine, llm: LLMSelection) {
    aiEngine == .memora ? (.cloud, MemoraIntelligence.selection) : (aiEngine, aiSelection)
  }

  var askAIModelName: String {
    registeredLLMs.selectedModel?.name ?? "Auto"
  }

  /// The summary sheet starts on the model Ask AI is using, so a model
  /// registered and chosen there writes summaries too.
  var defaultSummaryEngineChoice: SummaryEngineChoice {
    registeredLLMs.selectedModel.map { .registered($0.id) } ?? .settings
  }

  func summaryConfiguration(for choice: SummaryEngineChoice) -> (engine: AIEngine, llm: LLMSelection) {
    switch choice {
    case .settings:
      return settingsAIConfiguration
    case .onDevice:
      return (.foundation, aiSelection)
    case .registered(let id):
      guard let model = registeredLLMs.models.first(where: { $0.id == id }) else {
        return settingsAIConfiguration
      }
      return (.cloud, model.selection)
    }
  }
}
