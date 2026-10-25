import SwiftUI

struct SummaryGenerationSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var mode = SummaryGenerationMode.automatic
  @State private var template = SummaryTemplateChoice.standard
  /// The AI for this summary only. Unset starts on the one Ask AI uses.
  @State private var engineChoice: SummaryEngineChoice?
  @State private var selectedDetent = PresentationDetent.medium
  @State private var length = SummaryLength.standard
  @State private var processingMode = SummaryProcessingMode.balanced
  @State private var useCaseID = ""
  @State private var confirmsCloudDisclosure = false
  var meetingID: UUID

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: 22) {
            VStack(spacing: 8) {
              generationChoice(
                mode: .automatic,
                title: model.summaryPreferences.method.title,
                detail: automaticDetail,
                symbol: .sparkles
              )
              generationChoice(
                mode: .custom,
                title: "カスタム生成",
                detail: "テンプレートを選択して要約",
                symbol: .rectangleGrid2x2
              )
            }

            if mode == .custom {
              VStack(alignment: .leading, spacing: 12) {
                Text("テンプレートを選択")
                  .font(.title3.bold())

                VStack(spacing: 8) {
                  ForEach(choices) { item in
                    templateChoice(item)
                  }
                }
              }
              .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Picker("この記録の用途", selection: $useCaseID) {
              Text("指定しない").tag("")
              ForEach(OccupationCatalog.useCases) { useCase in
                Text(useCase.title).tag(useCase.id)
              }
            }
            .pickerStyle(.menu)
            Picker("要約の詳しさ", selection: $length) {
              ForEach(SummaryLength.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            SummaryProcessingPicker(mode: $processingMode, supportsControl: usesCloud &&
              SummaryGenerationPolicy.supportsThinkingControl(model.summaryConfiguration(for: selectedEngine).llm))
            if case .market(let selected) = resolvedChoice, let notice = selected.sensitivityClassification.notice {
              Text(notice).font(.footnote).foregroundStyle(.secondary)
            }
            engineSection
            if usesCloud {
              Toggle("文字起こしを選択したAIサービスへ送信する", isOn: $confirmsCloudDisclosure)
                .font(.subheadline)
              Text("顧客・利用者・未成年者などの情報が含まれる場合は、録音・外部送信の同意と所属先の方針を確認してください。声の特徴量は送信しません。")
                .font(.footnote).foregroundStyle(.secondary)
              Text("前回の生成が途中で止まった場合も、AIサービス側では処理・課金が済んでいる可能性があります。再試行は新しいリクエストとなり、追加の利用料金が発生する場合があります。")
                .font(.footnote).foregroundStyle(.secondary)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, MemoraSpacing.xl)
          .padding(.top, MemoraSpacing.lg)
          .padding(.bottom, MemoraSpacing.lg)
        }

        generateAction
      }
      .navigationTitle("要約を生成")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }
        }
      }
      .animation(reduceMotion ? nil : .smooth, value: mode)
      .onChange(of: mode) { _, newValue in
        selectedDetent = newValue == .custom ? .large : .medium
      }
      .onAppear {
        length = model.summaryPreferences.length
        processingMode = model.summaryPreferences.processingMode
        useCaseID = model.meeting(id: meetingID)?.summaryUseCaseID ?? ""
        template = resolvedChoice
      }
      .onChange(of: selectedEngine) { _, _ in confirmsCloudDisclosure = false }
    }
    .presentationDetents([.medium, .large], selection: $selectedDetent)
    .presentationDragIndicator(.visible)
  }

  private var generateAction: some View {
    VStack(spacing: 8) {
      Text("生成を押すまでAI処理は始まりません")
        .font(.caption)
        .foregroundStyle(.secondary)

      Button {
        var preferences = model.summaryPreferences
        preferences.length = length
        preferences.processingMode = processingMode
        let started = model.generateSummary(
          meetingID,
          choice: resolvedChoice,
          configuration: model.summaryConfiguration(for: selectedEngine),
          automaticallySelect: mode == .automatic && model.summaryPreferences.method == .automatic && useCaseID.isEmpty,
          useCaseID: useCaseID,
          preferences: preferences,
          cloudDisclosureConfirmed: confirmsCloudDisclosure
        )
        if started { dismiss() }
      } label: {
        Text("生成")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(MemoraButtonStyle())
      .disabled((usesCloud && !confirmsCloudDisclosure) || model.processing.isActive(meetingID)
        || model.speakerAnalysisIDs.contains(meetingID))
    }
    .padding(.horizontal, MemoraSpacing.xl)
    .padding(.top, MemoraSpacing.md)
    .padding(.bottom, MemoraSpacing.md)
    .background(.bar)
  }

  private var selectedEngine: SummaryEngineChoice {
    engineChoice ?? model.defaultSummaryEngineChoice
  }

  private var usesCloud: Bool {
    let engine = AIEngineService.effectiveEngine(model.summaryConfiguration(for: selectedEngine).engine)
    return engine == .cloud || engine == .memora
  }

  private var resolvedChoice: SummaryTemplateChoice {
    guard mode == .automatic else { return template }
    guard let meeting = model.meeting(id: meetingID) else { return model.defaultSummaryChoice }
    return model.automaticSummaryChoice(for: meeting, useCaseID: useCaseID.isEmpty ? nil : useCaseID)
  }

  private var automaticDetail: String {
    if !useCaseID.isEmpty || model.summaryPreferences.method == .fixed {
      return "「\(resolvedChoice.title)」で整理"
    }
    return usesCloud
      ? "基本は「\(resolvedChoice.title)」。AIが記録内容に合う形式を選びます"
      : "端末内の内容ルール・仕事の推薦から「\(resolvedChoice.title)」を選択。AI分類ではありません"
  }

  private var engineSection: some View {
    let configuration = model.summaryConfiguration(for: selectedEngine)

    return VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("AIエンジン", icon: configuration.engine.symbol)
          .font(.headline)
        Spacer()
        Picker("AIエンジン", selection: Binding {
          selectedEngine
        } set: { engineChoice = $0 }) {
          Text("設定に従う（\(model.aiEngine.shortLabel)）").tag(SummaryEngineChoice.settings)
          Text("端末内AI").tag(SummaryEngineChoice.onDevice)
          ForEach(model.registeredLLMs.models) { registered in
            Text("\(registered.name)（\(registered.provider.label)）")
              .tag(SummaryEngineChoice.registered(registered.id))
          }
        }
        .pickerStyle(.menu)
        .labelsHidden()
      }

      // Cloud and on-device differ in depth, so the sheet says which is coming.
      Text(MeetingSummarizer.approach(for: configuration.engine, llm: configuration.llm))
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(MemoraSpacing.lg)
    .background(
      Color(uiColor: .secondarySystemBackground),
      in: RoundedRectangle(cornerRadius: MemoraRadius.card, style: .continuous)
    )
  }

  private var choices: [SummaryTemplateChoice] {
    var seen: Set<String> = []
    return (model.recommendedSummaryChoices + model.allSummaryChoices).filter { seen.insert($0.id).inserted }
  }

  private func generationChoice(
    mode candidate: SummaryGenerationMode,
    title: String,
    detail: String,
    symbol: MemoraIcon
  ) -> some View {
    Button {
      mode = candidate
    } label: {
      HStack(spacing: 14) {
        Image(icon: symbol, size: 20)
          .font(.title3.weight(.semibold))
          .frame(width: 30)
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
          Text(detail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Image(icon: mode == candidate ? .checkmarkCircleFill : .circle, size: 17)
          .foregroundStyle(.primary)
      }
      .padding(MemoraSpacing.lg)
      .background(
        mode == candidate
          ? Color.primary.opacity(0.07)
          : Color(uiColor: .secondarySystemBackground),
        in: RoundedRectangle(cornerRadius: MemoraRadius.card, style: .continuous)
      )
      .contentShape(RoundedRectangle(cornerRadius: MemoraRadius.card, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(mode == candidate ? .isSelected : [])
  }

  private func templateChoice(_ item: SummaryTemplateChoice) -> some View {
    let isSelected = template == item

    return Button {
      template = item
    } label: {
      HStack(spacing: 14) {
        Image(icon: item.symbol, size: 17)
          .font(.headline)
          .frame(width: 38, height: 38)
          .background(Color.primary.opacity(0.07), in: Circle())

        VStack(alignment: .leading, spacing: 3) {
          Text(item.title)
            .font(.headline)
            .foregroundStyle(.primary)

          Text(item.detail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
        }

        Spacer(minLength: 8)

        Image(icon: isSelected ? .checkmarkCircleFill : .circle, size: 17)
          .foregroundStyle(.primary)
      }
      .padding(MemoraSpacing.lg)
      .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
      .background(
        isSelected
          ? Color.primary.opacity(0.07)
          : Color(uiColor: .secondarySystemBackground),
        in: RoundedRectangle(cornerRadius: MemoraRadius.card, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: MemoraRadius.card, style: .continuous)
          .stroke(isSelected ? Color.primary.opacity(0.5) : Color.clear, lineWidth: 1.5)
      }
      .contentShape(RoundedRectangle(cornerRadius: MemoraRadius.card, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

private enum SummaryGenerationMode {
  case automatic
  case custom
}
