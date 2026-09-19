import SwiftUI

/// One chat bubble: the person on the right, the assistant on the left with the
/// reasoning tucked behind a disclosure.
struct AIMessageView: View {
  var message: AIChatMessage

  var body: some View {
    switch message.role {
    case .user:
      userBubble
    case .assistant:
      assistantReply
    }
  }

  private var userBubble: some View {
    HStack {
      Spacer(minLength: 44)

      Text(message.text)
        .font(.body)
        .foregroundStyle(.primary)
        .textSelection(.enabled)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
          Color(uiColor: .secondarySystemBackground),
          in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("あなた: \(message.text)")
  }

  @ViewBuilder
  private var assistantReply: some View {
    VStack(alignment: .leading, spacing: 12) {
      if message.isThinking {
        HStack(spacing: 10) {
          ThinkingOrbView(state: .searching, size: 20)
          Text("考えています…")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("考えています")
      } else {
        if let thinking = message.thinking, !thinking.isEmpty {
          DisclosureGroup {
            Text(thinking)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .lineSpacing(3)
              .padding(.top, 6)
          } label: {
            Label("思考を表示", systemImage: "sparkles")
              .font(.subheadline.weight(.medium))
              .foregroundStyle(.secondary)
          }
          .tint(.secondary)
        }

        Text(message.text)
          .font(.body)
          .lineSpacing(5)
          .textSelection(.enabled)
          .memoraTextReveal()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
