import SwiftUI

/// One chat bubble: the person on the right, the assistant on the left with the
/// reasoning tucked behind a disclosure.
struct AIMessageView: View {
  var message: AIChatMessage
  /// Only the latest reply streams; older ones are already settled.
  var animates = true

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

        StreamingText(text: message.text, lineSpacing: 5, animates: animates)
      }

      if !message.isThinking, !message.sources.isEmpty {
        sourceList
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// The records the answer was built from, each opening the record itself.
  private var sourceList: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("参照した記録")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      ForEach(message.sources) { source in
        NavigationLink {
          MeetingDetailView(meetingID: source.meetingID)
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "doc.text")
              .font(.caption)
            Text(source.title)
              .font(.subheadline)
              .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.tertiary)
          }
          .foregroundStyle(.primary)
          .padding(.horizontal, 12)
          .padding(.vertical, 9)
          .background(
            Color.primary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
          )
          .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("参照した記録: \(source.title)")
        .accessibilityHint("記録を開きます")
      }
    }
  }
}
