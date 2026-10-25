import SwiftUI

struct MeetingInfographicGenerationSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var snapshot: MeetingSummaryPosterSnapshot
  @State private var permitsCloud = false
  @State private var isGenerating = false
  @State private var failure: String?
  @State private var generationTask: Task<Void, Never>?

  var body: some View {
    let configuration = model.askAIConfiguration
    let cloud = AIEngineService.effectiveEngine(configuration.engine) == .cloud
    let permitted = !cloud || RecordAccessPolicy.allows(snapshot.privacy, purpose: .cloudAI, explicitCloudConsent: permitsCloud)
    NavigationStack {
      Form {
        Section("内容に合わせて図解") {
          Text("要約から結論・比較・数値・判断の流れなどを整理し、別の1枚を作ります。本文は変更しません。")
          Text(cloud ? configuration.llm.modelLabel : "オンデバイスAI").font(.footnote).foregroundStyle(.secondary)
          if cloud {
            Text("要約本文を選択中のクラウドAIへ送信します。通常のAPI利用料またはクレジットが発生する場合があります。開くだけでは送信しません。")
              .font(.footnote)
            if !RecordAccessPolicy.allows(snapshot.privacy, purpose: .cloudAI) {
              Toggle("この図解生成に限り、要約の外部送信を許可", isOn: $permitsCloud)
                .disabled(isGenerating)
            }
          }
        }
        Section {
          if isGenerating {
            ProgressView("内容を整理しています…")
            Text("この画面を閉じると生成を中止します。確定するまで既存の図解は置き換えません。")
              .font(.footnote).foregroundStyle(.secondary)
          } else {
            Button("図解を生成") { start(configuration) }
              .disabled(!permitted || !snapshot.isCurrent(in: model))
              .accessibilityIdentifier("summary.infographic.generate")
          }
          if let failure { Text(failure).font(.footnote).foregroundStyle(MemoraPalette.danger) }
          if !snapshot.isCurrent(in: model) { Text("要約またはアクセス状態が変わりました。閉じてからもう一度開いてください。") }
        }
      }
      .navigationTitle("AIで1枚に整理")
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button(isGenerating ? "中止" : "キャンセル") { generationTask?.cancel(); dismiss() } } }
      .interactiveDismissDisabled(isGenerating)
      .onDisappear { generationTask?.cancel() }
      .onChange(of: snapshot.isCurrent(in: model)) { _, current in if !current { generationTask?.cancel() } }
    }
  }

  private func start(_ configuration: (engine: AIEngine, llm: LLMSelection)) {
    guard !isGenerating else { return }
    isGenerating = true
    failure = nil
    generationTask = Task {
      do {
        try await model.generateMeetingInfographic(snapshot, configuration: configuration, cloudConsent: permitsCloud)
        dismiss()
      } catch is CancellationError {
        if !Task.isCancelled { failure = "要約またはアクセス状態が変わったため中止しました。" }
      } catch { failure = error.localizedDescription }
      isGenerating = false
    }
  }
}
