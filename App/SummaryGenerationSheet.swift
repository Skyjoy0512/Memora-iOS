import SwiftUI

struct SummaryGenerationSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var mode = SummaryGenerationMode.automatic
  @State private var template = SummaryTemplateChoice.standard
  /// The engine for this summary only. Unset follows the settings engine.
  @State private var engineChoice: AIEngine?
  @State private var selectedDetent = PresentationDetent.medium
  var meetingID: UUID

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: 22) {
            VStack(spacing: 8) {
              generationChoice(
                mode: .automatic,
                title: "自動生成",
                detail: "詳細な概要：トピックごとに要点・決定事項・アクション・未決事項を整理",
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

            engineSection
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 20)
          .padding(.top, 18)
          .padding(.bottom, 14)
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
    }
    .presentationDetents([.medium, .large], selection: $selectedDetent)
    .presentationDragIndicator(.visible)
  }

  private var generateAction: some View {
    VStack(spacing: 8) {
      Text("生成を押すまでAI処理は始まりません")
        .font(.caption)
        .foregroundStyle(.secondary)

      Button("生成") {
        model.generateSummary(
          meetingID,
          choice: mode == .automatic ? .standard : template,
          engine: selectedEngine
        )
        dismiss()
      }
      .font(.headline)
      .foregroundStyle(Color(uiColor: .systemBackground))
      .frame(maxWidth: .infinity, minHeight: 56)
      .background(Color(uiColor: .label), in: Capsule())
      .contentShape(Capsule())
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 20)
    .padding(.top, 10)
    .padding(.bottom, 12)
    .background(.bar)
  }

  private var selectedEngine: AIEngine {
    engineChoice ?? model.aiEngine
  }

  /// Engines a summary can run on. The local LLM is only listed while the
  /// settings still point at it, since this build does not ship one.
  private var engineOptions: [AIEngine] {
    AIEngine.allCases.filter { $0 != .local || model.aiEngine == .local }
  }

  private var engineSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("AIエンジン", icon: selectedEngine.symbol)
          .font(.headline)
        Spacer()
        Picker("AIエンジン", selection: Binding {
          selectedEngine
        } set: { engineChoice = $0 }) {
          ForEach(engineOptions) { engine in
            Text(engine.label).tag(engine)
          }
        }
        .pickerStyle(.menu)
        .labelsHidden()
      }

      // Cloud and on-device differ in depth, so the sheet says which is coming.
      Text(MeetingSummarizer.approach(for: selectedEngine, llm: model.aiSelection))
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(14)
    .background(
      Color(uiColor: .secondarySystemBackground),
      in: RoundedRectangle(cornerRadius: 18, style: .continuous)
    )
  }

  private var choices: [SummaryTemplateChoice] {
    SummaryTemplateChoice.builtInChoices + model.installedMarketTemplates.map { .market($0) }
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
        Image(icon: symbol)
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
        Image(icon: mode == candidate ? .checkmarkCircleFill : .circle)
          .foregroundStyle(.primary)
      }
      .padding(14)
      .background(
        mode == candidate
          ? Color.primary.opacity(0.07)
          : Color(uiColor: .secondarySystemBackground),
        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
      )
      .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        Image(icon: item.symbol)
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

        Image(icon: isSelected ? .checkmarkCircleFill : .circle)
          .foregroundStyle(.primary)
      }
      .padding(14)
      .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
      .background(
        isSelected
          ? Color.primary.opacity(0.07)
          : Color(uiColor: .secondarySystemBackground),
        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .stroke(isSelected ? Color.primary.opacity(0.5) : Color.clear, lineWidth: 1.5)
      }
      .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

private enum SummaryGenerationMode {
  case automatic
  case custom
}
