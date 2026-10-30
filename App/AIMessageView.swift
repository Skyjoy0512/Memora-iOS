import SwiftUI
import UIKit

/// One chat bubble: the person on the right, the assistant on the left with the
/// reasoning tucked behind a disclosure.
struct AIMessageView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var message: AIChatMessage
  /// Only the latest reply streams; older ones are already settled.
  var animates = true
  @State private var openDocument: MemoraDocument?
  @State private var editingTask: MemoraTask?
  /// A cited record opened from an inline citation.
  @State private var citedSource: ArtifactSourceTarget?
  @State private var isSourcesOpen = false
  @State private var savingWebReportID: UUID?

  var body: some View {
    switch message.role {
    case .user:
      userBubble
    case .assistant:
      assistantReply
    }
  }

  private var userBubble: some View {
    AIUserMessageView(text: message.text, attachmentName: message.attachment?.name) {
      model.restoreAIRequestToComposer(message)
    }
  }

  @ViewBuilder
  private var assistantReply: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let name = message.residentName {
        Label(name, icon: message.residentSymbol ?? .sparkles)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .accessibilityLabel("常駐エージェント \(name)")
        if message.isThinking, let id = message.residentAgentID {
          Button("実行を停止", icon: .stopFill) { model.cancelResident(id) }.frame(minHeight: 44)
        }
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

      if !message.text.isEmpty {
        // Memora's answer reads as plain text on the page, not a balloon.
        answerText
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      ForEach(message.webResearchReportIDs, id: \.self) { id in
        if let report = model.webResearch(id: id), !report.sources.isEmpty {
          NavigationLink("出典 \(report.sources.count)件") { WebResearchDetailView(reportID: id) }
            .frame(minHeight: 44)
          if !message.isThinking, report.savedProjectID == nil {
            Button("プロジェクトにまとめる") { savingWebReportID = id }.frame(minHeight: 44)
          }
        }
      }
      ForEach(message.documentIDs, id: \.self) { id in
        if let document = model.document(id: id) {
          AgentDocumentCard(document: document) { openDocument = document }
        }
      }
      ForEach(message.createdTaskIDs, id: \.self) { id in
        if let task = model.task(id: id) {
          Button { editingTask = model.task(id: id) } label: {
            Label(task.title, icon: .checklist)
              .font(.subheadline).multilineTextAlignment(.leading)
              .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          }.tint(MemoraPalette.textPrimary)
        }
      }

      if !message.isThinking, !message.text.isEmpty {
        AIReplyActionsRow(message: message,
          excerptCount: spokenSources.reduce(0) { $0 + $1.excerpts.count },
          isSourcesOpen: isSourcesOpen) { isSourcesOpen.toggle() }
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
    .animation(reduceMotion ? nil : MemoraMotion.control, value: isSourcesOpen)
    .sheet(isPresented: Binding(get: { savingWebReportID != nil }, set: { if !$0 { savingWebReportID = nil } })) {
      if let id = savingWebReportID { WebResearchSaveSheet(reportID: id) }
    }
    .sheet(item: $openDocument) { document in
      NavigationStack {
        DocumentDetailView(documentID: document.id, showsCloseButton: true)
      }
    }
    .sheet(item: $editingTask) { task in TaskEditView(task: task) }
    .sheet(item: $citedSource) { target in
      ArtifactSourceDetailView(target: target, workspaceID: model.artifactProvenance(for: message).workspaceID)
    }
  }

  /// The answer, with the records it really cited as inline links.
  private var answerText: some View {
    let report = message.webResearchReportIDs.last.flatMap { model.webResearch(id: $0) }
    let sent = report?.isChatSearch == true
      ? report?.sources.filter { report?.sentSourceIDs?.contains($0.id) == true } ?? [] : []
    let researched = !sent.isEmpty ? WebResearchContext.markdownLinked(message.text, sent: sent) : message.text
    let text = AnswerCitations.linked(researched, sources: message.sources,
      allowedTargets: model.answerCitationTargets(for: message))

    return AIResponseText(text: text, isStreaming: message.isThinking, messageID: message.id)
      .environment(\.openURL, OpenURLAction { url in
        if url.scheme == WebResearchContext.citationScheme {
          guard let source = WebResearchContext.source(for: url, sent: sent) else { return .discarded }
          return .systemAction(source.url)
        }
        if url.scheme == AnswerCitations.scheme || url.scheme?.lowercased() == "memora" {
          guard let target = model.answerCitationTarget(for: url, message: message) else { return .discarded }
          citedSource = target
          return .handled
        }
        return .systemAction
      })
  }

  /// Records with lines that can be played back.
  private var spokenSources: [AIChatSource] {
    message.sources.filter { !$0.excerpts.isEmpty }
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
        .padding(.horizontal, MemoraSpacing.md)
        .padding(.vertical, 9)
        .background(
          Color.primary.opacity(0.06),
          in: RoundedRectangle(cornerRadius: MemoraRadius.field, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: MemoraRadius.field, style: .continuous))
      }
    }
  }

  private func sourceHeader(_ source: AIChatSource) -> some View {
    HStack(spacing: 8) {
      Image(icon: .docText, size: 12)
      Text(source.title)
        .font(.subheadline)
        .lineLimit(1)
      Spacer(minLength: 4)
      Image(icon: .chevronRight, size: 11)
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
