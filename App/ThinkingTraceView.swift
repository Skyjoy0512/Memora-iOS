import SwiftUI

/// While the AI works, one line saying what kind of work it is — 考えています,
/// 記録を探しています, 回答を書いています, 作業しています — with the time since
/// the question was sent. The steps, search results and reasoning behind it
/// are kept on the message but not shown, and the line goes once the answer
/// is in.
struct ThinkingTraceView: View {
  @Environment(MemoraModel.self) private var model
  var message: AIChatMessage

  /// Shown only while a reply is being formed.
  static func hasTrace(_ message: AIChatMessage) -> Bool {
    message.isThinking
  }

  var body: some View {
    let isWaiting = model.pendingAgentApproval?.messageID == message.id
      || model.pendingAgentQuestions?.messageID == message.id

    HStack(spacing: 8) {
      Image(icon: .sparkle)
        .font(.footnote)
        .foregroundStyle(.secondary)
      if isWaiting {
        Text("確認を待っています")
          .foregroundStyle(.secondary)
      } else {
        ShimmerText(text: label)
        ElapsedText(since: message.createdAt)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.tertiary)
      }
    }
    .font(.footnote.weight(.medium))
    .padding(.vertical, 4)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  private var label: String {
    if let id = message.webResearchReportIDs.last, model.webResearchBusyIDs.contains(id) {
      return model.webResearch(id: id)?.status == .writing ? "回答を書いています" : "Webを検索しています"
    }
    if !message.webResearchReportIDs.isEmpty { return "Webを検索しています" }
    if !message.isAgentReply {
      return message.searchFinished ? "回答を書いています" : "記録を探しています"
    }
    return message.agentSteps.isEmpty ? "考えています" : "作業しています"
  }
}
