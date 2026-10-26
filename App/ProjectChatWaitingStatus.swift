import SwiftUI

/// Token updates invalidate this leaf without rebuilding settled chat rows.
struct ProjectChatWaitingStatus: View {
  @Environment(MemoraModel.self) private var model
  var threadID: UUID
  var stage: String

  var body: some View {
    if (model.projectChatPartialAnswers[threadID] ?? "").isEmpty {
      ConversationStatusLine(label: stage)
    }
  }
}
