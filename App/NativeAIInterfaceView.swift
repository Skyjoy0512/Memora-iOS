import Charts
import SwiftUI

struct NativeAIInterfaceView: View {
  @Environment(MemoraModel.self) private var model
  var interface: NativeAIInterface
  var messageID: UUID?

  var body: some View {
    let taskReferences = Set(interface.components.filter { $0.kind == .taskList || $0.kind == .actionBar }.flatMap { $0.items.compactMap(\.referenceID) })
    let context = model.interfaceRenderContext(messageID: messageID, taskIDs: taskReferences)
    VStack(alignment: .leading, spacing: 24) {
      ForEach(interface.components) { component in
        VStack(alignment: .leading, spacing: 12) {
          if let title = component.title, !title.isEmpty { Text(title).font(.headline) }
          content(component, message: context.message, taskIDs: context.taskIDs, sources: context.sources)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func content(_ component: NativeAIInterface.Component, message: AIChatMessage?, taskIDs: Set<UUID>, sources: [UUID: AIChatSource]) -> some View {
    switch component.kind {
    case .taskList, .actionBar:
      ForEach(component.items) { item in
        if let id = item.referenceID, let messageID, taskIDs.contains(id), let task = model.task(id: id) {
          VStack(alignment: .leading, spacing: 4) {
            Text(task.title).font(.body)
            Text(task.statusLabel).font(.caption).foregroundStyle(.secondary)
            if item.action == .completeTask, !task.isCompleted {
              Button("完了にする", icon: .checkmark) { model.completeInterfaceTask(id, messageID: messageID) }
                .frame(minHeight: 44).disabled(model.isAIChatResponding)
            }
          }
        } else { unavailable }
      }
    case .documentCard:
      ForEach(component.items) { item in
        if let id = item.referenceID, let messageID, message?.documentIDs.contains(id) == true,
           let document = model.document(id: id) {
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
            guard model.canUseInterfaceContext(messageID: messageID) else { return }
            model.openProject(id)
          }
            .frame(minHeight: 44).multilineTextAlignment(.leading)
        } else { unavailable }
      }
    case .sourceList:
      ForEach(component.items) { item in
        if let id = item.referenceID, let messageID, let source = sources[id], model.meeting(id: id) != nil {
          NavigationLink {
            AIInterfaceReferenceDestination(messageID: messageID, target: .meeting(id))
          } label: {
            Label(source.title, icon: .docText).multilineTextAlignment(.leading).frame(minHeight: 44)
          }
        } else { unavailable }
      }
    case .comparisonTable:
      // A wide table owns its horizontal scroll; surrounding chat stays flexible.
      ScrollView(.horizontal) {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
          GridRow {
            ForEach(Array((component.columns ?? []).enumerated()), id: \.offset) { _, column in
              Text(column).font(.subheadline.weight(.semibold)).frame(minWidth: 100, maxWidth: 180, alignment: .leading)
            }
          }
          ForEach(component.items) { item in
            GridRow {
              ForEach(Array((item.cells ?? []).enumerated()), id: \.offset) { _, cell in
                Text(cell).font(.subheadline).frame(minWidth: 100, maxWidth: 180, alignment: .leading)
              }
            }.accessibilityElement(children: .combine)
          }
        }.textSelection(.enabled)
      }
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
    }
  }

  private var unavailable: some View {
    Text("この項目は現在参照できません。必要な情報を改めて依頼してください。")
      .font(.footnote).foregroundStyle(.secondary)
  }
}

/// NavigationLink can construct destinations before a tap. The check belongs
/// in the destination's body so a list row never recomputes the global grants.
private struct AIInterfaceReferenceDestination: View {
  @Environment(MemoraModel.self) private var model
  var messageID: UUID
  var target: Target

  var body: some View {
    if model.canUseInterfaceContext(messageID: messageID) {
      switch target {
      case .document(let id): DocumentDetailView(documentID: id)
      case .meeting(let id): MeetingDetailView(meetingID: id)
      }
    } else {
      Text("この項目は現在参照できません。必要な情報を改めて依頼してください。")
        .font(.footnote).foregroundStyle(.secondary)
    }
  }

  enum Target { case document(UUID), meeting(UUID) }
}
