import SwiftUI

/// One in-place experience for notes, journal and chat; fetching is always an explicit action.
struct InlineLinkSummaryView: View {
  @Environment(MemoraModel.self) private var model
  @Binding var text: String
  var isComposing = false
  @State private var session = InlineLinkSession()
  @State private var task: Task<Void, Never>?
  @State private var editorInput = ComposerInputState()

  var body: some View {
    let configuration = model.askAIConfiguration
    let workspace = model.currentTeamID
    let destination = AIEngineService.effectiveEngine(configuration.engine) == .cloud
      ? configuration.llm.summaryDestination : "この端末のAI"
    // A stable container keeps detection tasks alive before the first card exists.
    VStack(alignment: .leading, spacing: 0) {
      if let url = session.url {
        VStack(alignment: .leading, spacing: MemoraSpacing.sm) {
          HStack(alignment: .top, spacing: MemoraSpacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
              Text(session.title).font(.subheadline.weight(.medium)).lineLimit(2)
              Text(url.host ?? "").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("リンクカードを閉じる", icon: .xmark) { stop(); session.skip() }
              .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
          }
          if session.isBusy {
            ShimmerText(text: session.status == .fetching ? "リンクを読み取っています" : "要約しています", isActive: true)
              .font(.footnote)
            Button("停止") { stop() }.frame(minHeight: 44)
          } else {
            if let summary = session.pendingSummary {
              Text(summary).font(.subheadline).lineLimit(5).textSelection(.enabled)
              Button("要約を挿入") { insert(url) }.frame(minHeight: 44)
                .disabled(isComposing || editorInput.value?.hasMarkedText == true)
            } else {
              Text("このリンクを要約しますか？").font(.subheadline)
              Text("取得先: \(url.host ?? "")。要約先: \(destination)。操作した場合だけ取得・生成します。")
                .font(.caption).foregroundStyle(.secondary)
              ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { linkActions(configuration: configuration, workspace: workspace) }
                VStack(alignment: .leading, spacing: 0) { linkActions(configuration: configuration, workspace: workspace) }
              }
            }
            if let notice = session.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            if let error = session.error { Text(error).font(.footnote).foregroundStyle(MemoraPalette.danger) }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, MemoraSpacing.sm)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inlineLink.card")
      }
    }
    .background { ComposerInputObserver(state: editorInput, isActive: session.url != nil) }
    .task(id: text) {
      try? await Task.sleep(for: .milliseconds(400))
      guard !Task.isCancelled else { return }
      session.update(text: text, isComposing: isComposing || editorInput.snapshot()?.hasMarkedText == true)
    }
    .onChange(of: isComposing) { _, composing in if !composing { session.update(text: text, isComposing: false) } }
    .onChange(of: model.currentTeamID) { _, _ in stop(); session.skip() }
    .onDisappear { stop() }
  }

  @ViewBuilder
  private func linkActions(configuration: (engine: AIEngine, llm: LLMSelection), workspace: String?) -> some View {
                Button("スキップ") { stop(); session.skip() }.frame(minHeight: 44)
                Button("リンクを確認") {
                  task = Task { _ = await session.fetch() }
                }.frame(minHeight: 44)
                Button(session.error == nil ? "要約する" : "再試行") {
                  task = Task {
                    await session.summarize(engine: configuration.engine, llm: configuration.llm) {
                      model.currentTeamID == workspace && !model.isRestoring && model.askAIConfiguration.engine == configuration.engine
                        && model.askAIConfiguration.llm == configuration.llm
                    }
                  }
                }.frame(minHeight: 44)
  }

  private func stop() { task?.cancel(); task = nil; session.cancel() }
  private func insert(_ url: URL) {
    guard !isComposing, editorInput.snapshot()?.hasMarkedText != true, let summary = session.pendingSummary,
          InlineURLDetector.urls(in: text).contains(url) else { return }
    text = InlineURLDetector.inserting(summary: summary, title: session.title, url: url, into: text)
    session.skip()
  }
}
