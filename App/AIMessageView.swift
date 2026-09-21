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
        if let details = message.details {
          DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
              detailRow("対象", details.scopeLabel)
              detailRow(
                "エンジン",
                details.modelLabel.map { "\(details.engineLabel) · \($0)" } ?? details.engineLabel
              )
              detailRow("参照した記録", "\(details.sourceCount)件")
              detailRow("生成", details.generatedAt.formatted(date: .abbreviated, time: .shortened))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, 6)
          } label: {
            Label("参照した記録・処理情報", systemImage: "info.circle")
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

  private func accessibilityLabel(for source: AIChatSource) -> String {
    var parts = ["参照した記録: \(source.title)"]
    if let start = source.start {
      parts.append(MemoraFormat.duration(start))
    }
    if let excerpt = source.excerpt {
      parts.append(excerpt)
    }
    return parts.joined(separator: "、")
  }

  private func detailRow(_ title: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(title)
        .foregroundStyle(.tertiary)
      Text(value)
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(title): \(value)")
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
          VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
              Image(systemName: "doc.text")
                .font(.caption)
              Text(source.title)
                .font(.subheadline)
                .lineLimit(1)
              if let start = source.start {
                Text(MemoraFormat.duration(start))
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(.secondary)
              }
              Spacer(minLength: 4)
              Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            }

            if let excerpt = source.excerpt {
              Text(excerpt)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
          }
          .foregroundStyle(.primary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 12)
          .padding(.vertical, 9)
          .background(
            Color.primary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
          )
          .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: source))
        .accessibilityHint("記録を開きます")
      }
    }
  }
}
