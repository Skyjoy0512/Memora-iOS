import SwiftUI

struct ProjectChatRow: View {
  var thread: ProjectChatThread
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var zoom

  var body: some View {
    NavigationLink {
      if reduceMotion {
        ProjectChatView(threadID: thread.id)
      } else {
        ProjectChatView(threadID: thread.id)
          .navigationTransition(.zoom(sourceID: thread.id, in: zoom))
      }
    } label: {
      VStack(alignment: .leading, spacing: 5) {
        Text(thread.title)
          .font(MemoraTypography.body.weight(.medium))
          .lineLimit(2)
        Text(preview)
          .font(MemoraTypography.secondary)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
      .contentShape(Rectangle())
      .accessibilityElement(children: .combine)
      .matchedTransitionSource(id: thread.id, in: zoom)
    }
    .buttonStyle(.plain)
  }

  /// The last thing said in the thread, as ChatGPT-style project lists do; a
  /// thread with no turns still says what it is.
  private var preview: String {
    if let text = thread.messages.last?.text.trimmingCharacters(in: .whitespacesAndNewlines),
       !text.isEmpty {
      return text.replacingOccurrences(of: "\n", with: " ")
    }
    return thread.projectID == nil ? "保管した会話" : "まだメッセージはありません"
  }
}
