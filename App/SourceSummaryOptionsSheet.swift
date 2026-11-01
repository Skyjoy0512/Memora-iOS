import SwiftUI

struct SourceSummaryOptionsSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var sourceID: UUID
  @State private var options = SourceSummaryOptions()
  @State private var expectedSource: ProjectSource?
  @State private var workspaceGeneration: UUID?
  @State private var didPrepare = false
  @State private var showsPrivacy = false
  @State private var startFailure: String?

  var body: some View {
    NavigationStack {
      MemoraForm {
        Section {
          Picker("まとめ方", selection: $options.templateID) {
            Text("内容に合わせる").tag(String?.none)
            ForEach(templates) { template in
              Text(template.title).tag(Optional(template.id))
            }
            if let id = options.templateID, !templates.contains(where: { $0.id == id }) {
              Text(model.summaryChoice(id)?.title ?? "保存済みのテンプレート（利用できません）").tag(Optional(id))
            }
          }
          .pickerStyle(.navigationLink)

          Picker("詳しさ", selection: $options.length) {
            Text("設定に従う（\(model.summaryPreferences.length.title)）").tag(SummaryLength?.none)
            ForEach(SummaryLength.allCases) { length in Text(length.title).tag(Optional(length)) }
          }

          Picker("AI", selection: $options.engineChoice) {
            Text("AskAIに従う").tag(SummaryEngineChoice?.none)
            Text("設定に従う（\(model.aiEngine.shortLabel)）").tag(Optional(SummaryEngineChoice.settings))
            Text("端末内AI").tag(Optional(SummaryEngineChoice.onDevice))
            ForEach(model.registeredLLMs.models) { registered in
              Text(registered.name).tag(Optional(SummaryEngineChoice.registered(registered.id)))
            }
            if let choice = options.engineChoice, case .registered(let id) = choice,
               !model.registeredLLMs.models.contains(where: { $0.id == id }) {
              Text("保存済みのAIモデル（利用できません）").tag(options.engineChoice)
            }
          }
        } footer: {
          Text("この資料の要約に使います。原文を取り直さず、保存した内容から作成します。")
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) { generateAction }
      .navigationTitle("要約の設定").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }
        }
      }
      .onAppear {
        guard !didPrepare else { return }
        didPrepare = true
        expectedSource = model.source(id: sourceID)
        workspaceGeneration = model.aiWorkspaceGeneration
        options = model.sourceSummaryOptions(for: sourceID)
      }
      .onChange(of: options) { _, _ in startFailure = nil }
      .sheet(isPresented: $showsPrivacy, onDismiss: acceptPrivacyEdit) {
        if let source = model.source(id: sourceID) { ProjectSourcePrivacySheet(source: source) }
      }
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
  }

  private var generateAction: some View {
    let configuration = model.sourceSummaryConfiguration(for: options)
    let cloud = configuration.map { configuration in
      let engine = AIEngineService.effectiveEngine(configuration.engine)
      return engine == .cloud || engine == .memora
    } ?? false
    let renderedSource = model.source(id: sourceID)
    let renderedOptions = options
    let configurationIdentity = model.summaryConfigurationIdentity
    let reason = unavailableReason
    return VStack(spacing: MemoraSpacing.md) {
      if cloud, let configuration {
        Text("\(configuration.llm.summaryDestination)へ資料の本文を送信")
          .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      if let message = reason ?? startFailure {
        Text(message).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      if cloud, let source = renderedSource, isSameSource(source),
         !RecordAccessPolicy.allows(source.privacy, purpose: .cloudAI) {
        Button("送信の許可を確認") { showsPrivacy = true }.frame(minHeight: 44)
      }
      Button {
        startFailure = nil
        guard workspaceGeneration == model.aiWorkspaceGeneration,
              let renderedSource, isSameSource(renderedSource) else {
          startFailure = "資料が更新されました。設定を確認して開き直してください。"
          return
        }
        if model.startProjectSourceSummary(sourceID, options: renderedOptions, expectedSource: renderedSource,
          configurationIdentity: configurationIdentity) {
          dismiss()
        } else {
          startFailure = unavailableReason ?? model.persistenceFailureMessage
            ?? "開始できませんでした。設定は残しています。内容と送信先を確認して、もう一度お試しください。"
        }
      } label: {
        Text(cloud ? "送信して要約" : "要約する").frame(maxWidth: .infinity)
      }
      .buttonStyle(MemoraButtonStyle())
      .disabled(reason != nil)
    }
    .padding(MemoraSpacing.screen).background(.bar)
  }

  private var unavailableReason: String? {
    guard didPrepare else { return "資料を確認しています…" }
    guard workspaceGeneration == model.aiWorkspaceGeneration else {
      return "保存先が変わりました。資料を開き直してください。"
    }
    guard let source = model.source(id: sourceID) else { return "資料が見つかりません。開き直してください。" }
    guard isSameSource(source) else {
      return "資料が更新されました。選んだ設定はこの画面に残しています。資料を確認して開き直してください。"
    }
    return model.sourceSummaryUnavailableReason(id: sourceID, options: options)
  }

  private var templates: [SummaryTemplateChoice] {
    var seen = Set<String>()
    return model.allSummaryChoices.filter { $0.id != SummaryTemplateChoice.adaptive.id && seen.insert($0.id).inserted }
  }

  private func isSameSource(_ current: ProjectSource) -> Bool {
    guard let expectedSource else { return false }
    return expectedSource.hasSameReadableEvidence(as: current) && expectedSource.summaryOptions == current.summaryOptions
  }

  private func acceptPrivacyEdit() {
    guard workspaceGeneration == model.aiWorkspaceGeneration,
          var previous = expectedSource, let current = model.source(id: sourceID),
          previous.summaryOptions == current.summaryOptions else { return }
    previous.privacy = current.privacy
    guard previous.hasSameReadableEvidence(as: current) else { return }
    expectedSource = current
    startFailure = nil
  }
}
