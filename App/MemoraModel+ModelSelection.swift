import Foundation

extension MemoraModel {
  /// Capture once per question so changing the menu cannot reroute an answer
  /// already in flight. Auto follows the explicit settings engine policy.
  var askAIConfiguration: (engine: AIEngine, llm: LLMSelection) {
    if let registered = registeredLLMs.selectedModel {
      return (.cloud, registered.selection)
    }
    return (aiEngine, aiSelection)
  }

  var askAIModelName: String {
    registeredLLMs.selectedModel?.name ?? "Auto"
  }
}
