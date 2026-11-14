import SwiftUI

/// Live status stays compact; actual tool events remain available on demand.
struct ThinkingTraceView: View {
  @Environment(MemoraModel.self) private var model
  var message: AIChatMessage
  var isWaitingForApproval = false
  var permitsShimmer = true
  @State private var source: ArtifactSourceTarget?

  /// Shown only while a reply is being formed.
  static func hasTrace(_ message: AIChatMessage) -> Bool {
    message.isThinking || !message.agentSteps.isEmpty
  }

  var body: some View {
    let isWaiting = isWaitingForApproval || model.pendingAgentApproval?.messageID == message.id
      || model.pendingAgentQuestions?.messageID == message.id

    VStack(alignment: .leading, spacing: 0) {
      if message.isThinking && (message.text.isEmpty || isWaiting) {
        HStack(spacing: MemoraSpacing.sm) {
          MemoraThinkingLogo(isAnimating: !isWaiting)
          ConversationStatusLine(label: isWaiting ? "確認を待っています" : label,
            since: message.createdAt, isWaiting: isWaiting, showsShimmer: message.text.isEmpty && permitsShimmer)
        }
        .transition(.opacity)
      }
      if !message.agentSteps.isEmpty {
        AgentActivityView(steps: message.agentSteps, isRunning: message.isThinking, isWaiting: isWaiting,
          startedAt: message.createdAt) { id in
          let target = ArtifactSourceTarget.record(.meeting(id))
          guard model.answerCitationTargets(for: message).contains(target),
                model.canOpenArtifactSource(target, workspaceID: model.artifactProvenance(for: message).workspaceID) else { return }
          source = target
        }
      }
    }
    .sheet(item: $source) { target in
      ArtifactSourceDetailView(target: target, workspaceID: model.artifactProvenance(for: message).workspaceID)
    }
  }

  private var label: String {
    if let id = message.webResearchReportIDs.last, model.webResearchBusyIDs.contains(id) {
      return model.webResearch(id: id)?.status == .writing ? "回答を書いています" : "Webを検索しています"
    }
    if !message.isAgentReply {
      return message.searchFinished ? "回答を書いています" : "記録を探しています"
    }
    if !message.text.isEmpty { return "回答を書いています" }
    return message.agentSteps.isEmpty ? "考えています" : "作業しています"
  }
}
