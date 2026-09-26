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
              detailRow("AIに渡した参考資料", "\(details.sourceCount)件")
              detailRow("生成", details.generatedAt.formatted(date: .abbreviated, time: .shortened))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, 6)
          } label: {
            Label("AIに渡した参考資料・処理情報", icon: .infoCircle)
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
    var parts = ["AIに渡した参考資料: \(source.title)"]
    parts.append(contentsOf: source.excerpts.map { MemoraFormat.duration($0.start) + "、" + $0.text })
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

  /// The records the answer was built from, each opening the record; each stored
  /// excerpt in it plays from its own time.
  private var sourceList: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("AIに渡した参考資料")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      ForEach(message.sources) { source in
        VStack(alignment: .leading, spacing: 6) {
          NavigationLink {
            MeetingDetailView(meetingID: source.meetingID)
          } label: {
            sourceHeader(source)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(accessibilityLabel(for: source))
          .accessibilityHint("記録を開きます")

          ForEach(Array(source.excerpts.enumerated()), id: \.offset) { _, excerpt in
            NavigationLink {
              MeetingDetailView(meetingID: source.meetingID, initialPlaybackStart: excerpt.start)
            } label: {
              excerptRow(excerpt)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(MemoraFormat.duration(excerpt.start))、\(excerpt.text)")
            .accessibilityHint("この位置から再生します")
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
          Color.primary.opacity(0.06),
          in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      }
    }
  }

  private func sourceHeader(_ source: AIChatSource) -> some View {
    HStack(spacing: 8) {
      Image(icon: .docText)
        .font(.caption)
      Text(source.title)
        .font(.subheadline)
        .lineLimit(1)
      Spacer(minLength: 4)
      Image(icon: .chevronRight)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.tertiary)
    }
    .foregroundStyle(.primary)
  }

  private func excerptRow(_ excerpt: AIChatSource.Excerpt) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Text(MemoraFormat.duration(excerpt.start))
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
      Text(excerpt.text)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
