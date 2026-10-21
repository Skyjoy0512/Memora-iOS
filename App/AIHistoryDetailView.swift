import SwiftUI

/// One stored exchange: the question, the answer that was given, and what
/// produced it. Asking it again is a separate choice, so opening a history
/// entry never sends anything.
struct AIHistoryDetailView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var entry: AIConversationEntry
  var ask: (String) -> Void
  /// Opens this exchange as the conversation, to follow up on it.
  var continueConversation: ((AIConversationEntry) -> Void)?
  var openProjectAction: ((UUID) -> Void)?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 6) {
          Text("質問")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          Text(entry.question)
            .font(.headline)
            .textSelection(.enabled)
        }

        VStack(alignment: .leading, spacing: 6) {
          Text("回答")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          Text(entry.answer)
            .memoraReadingText()
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        VStack(alignment: .leading, spacing: 6) {
          detailRow("対象", entry.scopeLabel)
          detailRow("エンジン", engineLabel)
          detailRow("日時", entry.createdAt.formatted(date: .abbreviated, time: .shortened))
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)

        if let id = entry.webResearchReportID, model.webResearch(id: id) != nil {
          NavigationLink("出典・プロジェクトへの保存") { WebResearchDetailView(reportID: id, openProjectAction: openProjectAction) }
            .frame(minHeight: 44)
        }
        if let continueConversation {
          Button {
            dismiss()
            continueConversation(entry)
          } label: {
            Label("この会話の続きから", icon: .bubbleLeftAndBubbleRight)
              .font(.headline)
              .frame(maxWidth: .infinity, minHeight: 48)
          }
          .buttonStyle(.borderedProminent)
          .tint(MemoraPalette.action)
          .foregroundStyle(MemoraPalette.actionLabel)
        }

        Button {
          dismiss()
          ask(entry.question)
        } label: {
          Label("もう一度聞く", icon: .arrowClockwise)
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.bordered)
        .tint(MemoraPalette.textPrimary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(MemoraSpacing.lg)
    }
    .background(MemoraPalette.background)
    .navigationTitle("質問履歴")
    .navigationBarTitleDisplayMode(.inline)
  }

  /// What really answered, recorded with the entry rather than read from
  /// today's settings.
  private var engineLabel: String {
    guard let engine = entry.engineLabel else { return "記録なし" }
    guard let model = entry.modelLabel else { return engine }
    return "\(engine) · \(model)"
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
}
