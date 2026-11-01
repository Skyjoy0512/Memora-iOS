import Foundation

/// Preparation may outlive the visible draft, conversation or workspace.
/// Revalidate the whole request before dispatch, even if a view callback has
/// not yet observed the change and cancelled its task.
@MainActor
struct AIComposerRequestContext {
  var draft: String
  var attachment: AIAttachment?
  var mentions: [ComposerMention]
  var configuration: (engine: AIEngine, llm: LLMSelection)
  private var generation: UUID
  private var conversationID: UUID
  private var tab: RootTab
  private var path: [LibraryRoute]
  private var scope: AIQueryScope

  init?(scope: AIQueryScope, in model: MemoraModel) {
    guard !Task.isCancelled, model.currentTeamID == nil, !model.isRestoring,
          !model.isStoreProtected, !model.isToolsPresented else { return nil }
    draft = model.composerDraft
    attachment = model.composerAttachment
    mentions = model.composerMentions
    configuration = model.askAIConfiguration
    generation = model.aiWorkspaceGeneration
    conversationID = model.aiConversationID
    tab = model.selectedTab
    path = model.activeNavigationPath
    self.scope = scope
  }

  func isCurrent(in model: MemoraModel, scope: AIQueryScope) -> Bool {
    self.scope == scope && !Task.isCancelled && model.currentTeamID == nil && !model.isRestoring &&
      !model.isStoreProtected && !model.isToolsPresented &&
      model.aiWorkspaceGeneration == generation && model.aiConversationID == conversationID &&
      model.selectedTab == tab && model.activeNavigationPath == path &&
      model.composerDraft == draft && model.composerAttachment == attachment &&
      model.composerMentions == mentions && model.askAIConfiguration.engine == configuration.engine &&
      model.askAIConfiguration.llm == configuration.llm
  }
}
