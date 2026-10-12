import SwiftUI
import UIKit

/// One chat bubble: the person on the right, the assistant on the left with the
/// reasoning tucked behind a disclosure.
struct AIMessageView: View {
  @Environment(MemoraModel.self) private var model
  var message: AIChatMessage
  /// Only the latest reply streams; older ones are already settled.
  var animates = true
  @State private var openDocument: MemoraDocument?
  /// A cited record opened from an inline citation.
  @State private var citedRecord: AIChatSource?
  @State private var isSourcesOpen = false

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
        .textSelection(.enabled)
        .aiBubble()
        .contextMenu {
          Button("コピー", icon: .docOnDoc) {
            UIPasteboard.general.string = message.text
          }
          Button("入力欄に戻す", icon: .arrowUturnBackward) {
            model.composerDraft = message.text
          }
        }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("あなた: \(message.text)")
  }

  @ViewBuilder
  private var assistantReply: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let name = message.residentName {
        Label(name, icon: message.residentSymbol ?? .sparkles)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .accessibilityLabel("常駐エージェント \(name)")
      }

      // The trace: open while the AI works, one settled line afterwards.
      if ThinkingTraceView.hasTrace(message) {
        ThinkingTraceView(message: message)
      }

      if let approval = model.pendingAgentApproval, approval.messageID == message.id {
        AgentApprovalCard(approval: approval)
          .transition(.opacity.combined(with: .scale(scale: 0.97)))
      }

      if let questions = model.pendingAgentQuestions, questions.messageID == message.id {
        AgentQuestionCard(request: questions)
          .id(questions.id)
          .transition(.opacity.combined(with: .move(edge: .bottom)))
      }

      if !message.isThinking, !message.text.isEmpty {
        // Memora's answer reads as plain text on the page, not a balloon.
        answerText
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      ForEach(message.webResearchReportIDs, id: \.self) { id in
        NavigationLink("Web調査結果とソース") { WebResearchDetailView(reportID: id) }
          .frame(minHeight: 44)
      }
      ForEach(message.documentIDs, id: \.self) { id in
        if let document = model.document(id: id) {
          AgentDocumentCard(document: document) { openDocument = document }
        }
      }

      if !message.isThinking, !message.text.isEmpty {
        HStack(spacing: 8) {
          AIAnswerActions(message: message)
          if !spokenSources.isEmpty {
            sourcesToggle
          }
        }
        // The lines worth playing back, folded until asked for.
        if isSourcesOpen, !spokenSources.isEmpty {
          sourceList
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
      }

      let followUps = model.followUps(for: message)
      if !followUps.isEmpty {
        AIFollowUpList(prompts: followUps, title: message.suggestions.isEmpty ? "続けて聞く" : "提案") {
          model.sendAIChat($0)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .animation(MemoraMotion.control, value: isSourcesOpen)
    .sheet(item: $openDocument) { document in
      NavigationStack {
        DocumentDetailView(documentID: document.id, showsCloseButton: true)
      }
    }
    .sheet(item: $citedRecord) { source in
      NavigationStack {
        MeetingDetailView(meetingID: source.meetingID, showsLocalPlaybackBar: true)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              ToolbarIconButton("閉じる", icon: .xmark) { citedRecord = nil }
            }
          }
      }
    }
  }

  /// The answer, with the records it really cited as inline links.
  @ViewBuilder
  private var answerText: some View {
    if !message.isAgentReply, AnswerCitations.hasCitations(message.text, sources: message.sources) {
      StreamingText(
        text: AnswerCitations.linked(message.text, sources: message.sources),
        lineSpacing: 5,
        animates: animates,
        revealText: AnswerCitations.stripped(message.text)
      )
      .environment(\.openURL, OpenURLAction { url in
        guard let source = AnswerCitations.source(for: url, in: message.sources) else { return .systemAction }
        citedRecord = source
        return .handled
      })
    } else {
      StreamingText(text: AnswerCitations.stripped(message.text), lineSpacing: 5, animates: animates)
    }
  }

  /// Records with lines that can be played back.
  private var spokenSources: [AIChatSource] {
    message.sources.filter { !$0.excerpts.isEmpty }
  }

  private var sourcesToggle: some View {
    Button {
      isSourcesOpen.toggle()
    } label: {
      HStack(spacing: 6) {
        HStack(spacing: -4) {
          ForEach(Array(spokenSources.prefix(3).enumerated()), id: \.offset) { index, _ in
            Circle()
              .fill(MemoraPalette.textSecondary.opacity(1 - Double(index) * 0.2))
              .frame(width: 12, height: 12)
              .overlay(Circle().stroke(MemoraPalette.background, lineWidth: 1.5))
          }
        }
        Text("\(spokenSources.reduce(0) { $0 + $1.excerpts.count })か所の発言")
          .font(.caption)
          .foregroundStyle(.secondary)
        Image(icon: .chevronDown)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.tertiary)
          .rotationEffect(.degrees(isSourcesOpen ? 180 : 0))
      }
      .padding(.horizontal, 6)
      .frame(minHeight: 36)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("根拠になった発言")
    .accessibilityValue(isSourcesOpen ? "開いています" : "閉じています")
  }

  private func accessibilityLabel(for source: AIChatSource) -> String {
    var parts = ["AIに渡した参考資料: \(source.title)"]
    parts.append(contentsOf: source.excerpts.map { MemoraFormat.duration($0.start) + "、" + $0.text })
    return parts.joined(separator: "、")
  }

  /// The records the answer was built from, each opening the record; each stored
  /// excerpt in it plays from its own time.
  private var sourceList: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(spokenSources) { source in
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
        .foregroundStyle(.primary)
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
