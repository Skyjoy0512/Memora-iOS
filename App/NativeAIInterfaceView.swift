import Charts
import SwiftUI

struct NativeAIInterfaceView: View {
  @Environment(MemoraModel.self) private var model
  var interface: NativeAIInterface
  var messageID: UUID?
  var allowsInteractions = true
  @State private var mailDraft: MailDraft?

  var body: some View {
    let leaves = interface.components.flatMap { $0.components ?? [$0] }
    let taskReferences = Set(leaves.filter { $0.kind == .taskList || $0.kind == .actionBar || $0.kind == .taskProgress }.flatMap { $0.items.compactMap(\.referenceID) })
    let context = model.interfaceRenderContext(messageID: messageID, taskIDs: taskReferences)
    VStack(alignment: .leading, spacing: 24) {
      ForEach(interface.components) { component in
        block(component, message: context.message, taskIDs: context.taskIDs, sources: context.sources)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .sheet(item: $mailDraft) { draft in
      if let messageID, let current = model.interfaceMailDraft(draft.id, messageID: messageID) {
        MailDraftSheet(draft: current) { mailDraft = nil }
      } else { unavailable }
    }
  }

  /// One titled block of the answer. Used for the top-level components and for
  /// the children of a Row/Column, so a nested part keeps its own heading.
  @ViewBuilder
  private func block(_ component: NativeAIInterface.Component, message: AIChatMessage?, taskIDs: Set<UUID>, sources: [UUID: AIChatSource]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      if component.kind != .disclosure, let title = component.title, !title.isEmpty { Text(title).font(.headline) }
      content(component, message: message, taskIDs: taskIDs, sources: sources)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func content(_ component: NativeAIInterface.Component, message: AIChatMessage?, taskIDs: Set<UUID>, sources: [UUID: AIChatSource]) -> some View {
    switch component.kind {
    case .row, .column:
      // A read-only layout of the parts beside or above one another. Only real,
      // permitted records reach the children, exactly as at the top level.
      let children = component.components ?? []
      let layout = component.kind == .row
        ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
      layout {
        ForEach(children) { child in
          // AnyView erases the type here so the recursive block/content pair is
          // not an opaque type defined in terms of itself.
          AnyView(block(child, message: message, taskIDs: taskIDs, sources: sources))
        }
      }
    case .taskList, .actionBar:
      ForEach(component.items) { item in
        if let id = item.referenceID, let messageID, taskIDs.contains(id), let task = model.task(id: id) {
          VStack(alignment: .leading, spacing: 4) {
            Text(task.title).font(.body)
            Text(task.statusLabel).font(.caption).foregroundStyle(.secondary)
            if item.action == .completeTask, !task.isCompleted {
              Button("完了にする", icon: .checkmark) { model.completeInterfaceTask(id, messageID: messageID) }
                .frame(minHeight: 44).disabled(!allowsInteractions || model.isAIChatResponding)
            }
          }
        } else { unavailable }
      }
    case .documentCard:
      ForEach(component.items) { item in
        if let id = item.referenceID, let messageID, message?.documentIDs.contains(id) == true,
           let document = model.document(id: id),
           document.provenance.map({ $0.isValid && $0.workspaceID == message?.interfaceWorkspaceID }) ?? true {
          NavigationLink {
            AIInterfaceReferenceDestination(messageID: messageID, target: .document(id))
          } label: {
            Label(document.title, icon: .docText).multilineTextAlignment(.leading).frame(minHeight: 44)
          }
        } else { unavailable }
      }
    case .projectCard:
      ForEach(component.items) { item in
        if let id = item.referenceID, let messageID, message?.interfaceProjectIDs.contains(id) == true,
           let project = model.space(id: id) {
          Button(project.name, icon: .folder) {
            guard model.canOpenInterfaceReference(.project(id), messageID: messageID) else { return }
            model.openProject(id)
          }
            .frame(minHeight: 44).multilineTextAlignment(.leading)
        } else { unavailable }
      }
    case .sourceList:
      AIInterfaceSourceList(items: component.items, sources: sources, messageID: messageID,
        canOpen: { id in messageID.map { model.canOpenInterfaceReference(.meeting(id), messageID: $0) } ?? false })
    case .comparisonTable:
      // A wide table owns its horizontal scroll; surrounding chat stays flexible.
      AIInterfaceComparisonTable(columns: component.columns ?? [], items: component.items,
        messageID: messageID, evidenceTargets: evidenceTargets(component, messageID: messageID))
    case .timeline:
      ForEach(component.items) { item in
        VStack(alignment: .leading, spacing: 4) {
          Text(item.title ?? "").font(.subheadline.weight(.semibold))
          if let detail = item.detail { Text(detail).font(.body).foregroundStyle(.secondary) }
        }.accessibilityElement(children: .combine).textSelection(.enabled)
      }
    case .chart:
      Chart(component.items) { item in
        BarMark(x: .value("値", item.value ?? 0), y: .value("項目", item.title ?? ""))
          .foregroundStyle(MemoraPalette.textPrimary)
          .accessibilityLabel(item.title ?? "").accessibilityValue((item.value ?? 0).formatted())
      }
      .chartXAxis { AxisMarks { AxisValueLabel().foregroundStyle(MemoraPalette.textSecondary) } }
      .chartYAxis { AxisMarks { AxisValueLabel().foregroundStyle(MemoraPalette.textSecondary) } }
      .frame(height: CGFloat(max(160, component.items.count * 36)))
      ForEach(component.items) { item in
        LabeledContent(item.title ?? "", value: (item.value ?? 0).formatted()).font(.caption)
      }
    case .taskProgress:
      let references = component.items.compactMap(\.referenceID)
      let tasks = references.compactMap { model.task(id: $0) }
      if Set(references).isSubset(of: taskIDs), tasks.count == references.count {
        AIInterfaceTaskProgress(tasks: tasks)
      } else { unavailable }
    case .mailDraftCard:
      ForEach(component.items) { item in
        if let id = item.referenceID, let messageID, let draft = model.interfaceMailDraft(id, messageID: messageID) {
          Button {
            guard allowsInteractions, let current = model.interfaceMailDraft(id, messageID: messageID) else { return }
            mailDraft = current
          } label: {
            VStack(alignment: .leading, spacing: 6) {
              Label(draft.subject.isEmpty ? "メール下書き" : draft.subject, icon: .envelope).font(.subheadline.weight(.medium))
              Text(draft.body).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
              Text(draft.recipients.isEmpty ? "宛先未設定 · 下書き" : "下書き · 編集して確認").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
          }.buttonStyle(.plain).disabled(!allowsInteractions)
        } else { unavailable }
      }
    case .calendarPreview:
      if let messageID, let events = model.interfaceCalendarEvents(component.items.compactMap(\.referenceID), messageID: messageID),
         let readAt = message?.calendarReadSnapshot?.readAt {
        AIInterfaceCalendarPreview(events: events, readAt: readAt)
      } else { unavailable }
    case .disclosure:
      DisclosureGroup(component.title ?? "補足") {
        ForEach(component.items) { item in
          VStack(alignment: .leading, spacing: 4) {
            Text(item.title ?? "").font(.subheadline.weight(.medium))
            if let detail = item.detail { Text(detail).font(.body).foregroundStyle(.secondary) }
          }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, MemoraSpacing.sm)
            .accessibilityElement(children: .combine).textSelection(.enabled)
        }
      }.tint(.primary)
    }
  }

  /// Resolves a comparison row's optional evidence ID to a target the message
  /// still permits right now. Only a meeting, document or project the message
  /// actually holds can be returned, so a hallucinated or revoked ID simply
  /// leaves the row without a link.
  private func evidenceTargets(_ component: NativeAIInterface.Component, messageID: UUID?) -> [UUID: AIInterfaceReferenceTarget] {
    guard let messageID else { return [:] }
    return AIInterfaceEvidence.targets(for: component.items.compactMap(\.referenceID)) { target in
      model.canOpenInterfaceReference(target, messageID: messageID)
    }
  }

  private var unavailable: some View {
    Text("この項目は現在参照できません。必要な情報を改めて依頼してください。")
      .font(.footnote).foregroundStyle(.secondary)
  }
}

/// NavigationLink can construct destinations before a tap. The check belongs
/// in the destination's body so a list row never recomputes the global grants.
struct AIInterfaceReferenceDestination: View {
  @Environment(MemoraModel.self) private var model
  var messageID: UUID
  var target: AIInterfaceReferenceTarget

  var body: some View {
    if model.canOpenInterfaceReference(target, messageID: messageID) {
      switch target {
      case .document(let id): DocumentDetailView(documentID: id)
      case .meeting(let id): MeetingDetailView(meetingID: id)
      case .project: EmptyView()
      }
    } else {
      Text("この項目は現在参照できません。必要な情報を改めて依頼してください。")
        .font(.footnote).foregroundStyle(.secondary)
    }
  }
}
