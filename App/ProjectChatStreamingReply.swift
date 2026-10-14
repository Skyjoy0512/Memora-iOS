import SwiftUI

struct ProjectChatStreamingReply: View {
  @Environment(MemoraModel.self) private var model
  var threadID: UUID

  var body: some View {
    if let text = model.projectChatPartialAnswers[threadID], !text.isEmpty {
      AIResponseText(text: text, isStreaming: true)
    }
  }
}
