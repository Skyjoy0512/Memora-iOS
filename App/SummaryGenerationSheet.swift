import SwiftUI

struct SummaryGenerationSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var template: SummaryTemplateChoice?
  @State private var engineChoice: SummaryEngineChoice?
  @State private var length = SummaryLength.standard
  @State private var processingMode = SummaryProcessingMode.balanced
  @State private var useCaseID = ""
  @State private var startFailure: String?
  @State private var showsPrivacy = false
  @State private var didPrepare = false
  var meetingID: UUID

  var body: some View {
    NavigationStack {
      MemoraForm {
        Section {
          Picker("AI", selection: Binding {
            selectedEngine
          } set: { engineChoice = $0 }) {
            Text("設定に従う（\(model.aiEngine.shortLabel)）").tag(SummaryEngineChoice.settings)
            Text("端末内AI").tag(SummaryEngineChoice.onDevice)
            ForEach(model.registeredLLMs.models) { registered in
              Text(registered.name).tag(SummaryEngineChoice.registered(registered.id))
            }
          }
          .accessibilityIdentifier("summary.engineChoice")

          Picker("まとめ方", selection: $template) {
            Text("おまかせ").tag(SummaryTemplateChoice?.none)
            ForEach(choices) { choice in
              Text(choice.title).tag(Optional(choice))
            }
          }
          .pickerStyle(.navigationLink)
          .accessibilityIdentifier("summary.templateChoice")
        }

        Section("詳しさ") {
          Picker("詳しさ", selection: $length) {
            ForEach(SummaryLength.allCases) { Text($0.title).tag($0) }
          }
          .pickerStyle(.segmented)
          .accessibilityIdentifier("summary.length")
        }

        Section {
          DisclosureGroup("詳細設定") {
            Picker("用途", selection: $useCaseID) {
              Text("指定しない").tag("")
              ForEach(OccupationCatalog.useCases) { Text($0.title).tag($0.id) }
            }
            if usesCloud {
              SummaryProcessingPicker(mode: $processingMode, supportsControl:
                SummaryGenerationPolicy.supportsThinkingControl(model.summaryConfiguration(for: selectedEngine).llm))
            }
          }
          .accessibilityIdentifier("summary.advanced")
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) { generateAction }
      .navigationTitle("要約する")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }
        }
      }
      .onAppear {
        guard !didPrepare else { return }
        didPrepare = true
        length = model.summaryPreferences.length
        processingMode = model.summaryPreferences.processingMode
        useCaseID = model.meeting(id: meetingID)?.summaryUseCaseID ?? ""
      }
      .sheet(isPresented: $showsPrivacy) { RecordPrivacySettingsView(meetingID: meetingID) }
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
  }

  private var generateAction: some View {
    let configuration = model.summaryConfiguration(for: selectedEngine)
    let fingerprint = model.meeting(id: meetingID).flatMap(SummaryJobFingerprint.make)
    let workspace = model.aiWorkspaceGeneration
    return VStack(spacing: MemoraSpacing.md) {
      if usesCloud {
        Text("\(configuration.llm.summaryDestination)へ記録を送信")
          .font(.footnote).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("summary.destination")
      }
      if let message = unavailableReason ?? startFailure {
        Text(message).font(.footnote).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("summary.startFailure")
        if let meeting = model.meeting(id: meetingID), usesCloud,
           !RecordAccessPolicy.allowsSummarySubmission(meeting.effectivePrivacy) {
          Button("送信の許可を確認") { showsPrivacy = true }.frame(minHeight: 44)
        }
      }
      Button {
        startFailure = nil
        var preferences = model.summaryPreferences
        preferences.length = length
        preferences.processingMode = processingMode
        let started = model.generateSummary(
          meetingID, choice: resolvedChoice, configuration: configuration,
          automaticallySelect: template == nil && model.summaryPreferences.method == .automatic && useCaseID.isEmpty,
          useCaseID: useCaseID, preferences: preferences,
          submission: SummarySubmissionIntent(meetingID: meetingID, inputFingerprint: fingerprint,
            workspaceGeneration: workspace, engine: configuration.engine, llm: configuration.llm)
        )
        if started { dismiss() }
        else {
          startFailure = unavailableReason ?? model.persistenceFailureMessage
            ?? "開始できませんでした。もう一度お試しください。"
        }
      } label: {
        Text(usesCloud ? "送信して要約" : "要約する").frame(maxWidth: .infinity)
      }
      .buttonStyle(MemoraButtonStyle())
      .accessibilityIdentifier("summary.generate")
      .disabled(unavailableReason != nil)
    }
    .padding(MemoraSpacing.screen)
    .background(.bar)
  }

  private var unavailableReason: String? {
    guard let meeting = model.meeting(id: meetingID) else { return "記録が見つかりません。開き直してください。" }
    if meeting.transcript.allSatisfy({ $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
      return "要約できる文字起こしがありません。原文を確認してください。"
    }
    if model.currentTeamID != nil { return "このワークスペースでは要約を実行できません。" }
    if model.isRestoring { return "復元が終わってから要約できます。" }
    if model.isStoreProtected { return "保存領域を利用できません。端末のロックを解除して開き直してください。" }
    if model.processing.isActive(meetingID) || model.speakerAnalysisIDs.contains(meetingID) {
      return "この記録の処理が終わってから要約できます。"
    }
    if usesCloud && !RecordAccessPolicy.allowsSummarySubmission(meeting.effectivePrivacy) { return "この記録はクラウド送信がオフです" }
    return nil
  }

  private var selectedEngine: SummaryEngineChoice { engineChoice ?? model.defaultSummaryEngineChoice }

  private var usesCloud: Bool {
    let engine = AIEngineService.effectiveEngine(model.summaryConfiguration(for: selectedEngine).engine)
    return engine == .cloud || engine == .memora
  }

  private var resolvedChoice: SummaryTemplateChoice {
    if let template { return template }
    guard let meeting = model.meeting(id: meetingID) else { return model.defaultSummaryChoice }
    return model.automaticSummaryChoice(for: meeting, useCaseID: useCaseID.isEmpty ? nil : useCaseID)
  }

  private var choices: [SummaryTemplateChoice] {
    var seen: Set<String> = []
    return (model.recommendedSummaryChoices + model.allSummaryChoices).filter { seen.insert($0.id).inserted }
  }
}
