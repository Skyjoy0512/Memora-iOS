import SwiftUI

struct SummaryGenerationSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var mode = SummaryGenerationMode.automatic
  @State private var template = SummaryTemplate.meetingMinutes
  @State private var aiModel = SummaryAIModel.standard
  @State private var selectedDetent = PresentationDetent.medium
  var meetingID: UUID

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          VStack(spacing: 8) {
            generationChoice(
              mode: .automatic,
              title: "自動生成",
              detail: "内容に応じて最適な形に自動要約",
              symbol: "sparkles"
            )
            generationChoice(
              mode: .custom,
              title: "カスタム生成",
              detail: "テンプレートを選択して要約",
              symbol: "rectangle.grid.2x2"
            )
          }

          if mode == .custom {
            VStack(alignment: .leading, spacing: 12) {
              Text("テンプレートを選択")
                .font(.title3.bold())

              ScrollView(.horizontal) {
                HStack(spacing: 12) {
                  ForEach(SummaryTemplate.allCases.filter { $0 != .automatic }) { item in
                    Button {
                      template = item
                    } label: {
                      VStack(alignment: .leading, spacing: 8) {
                        Text(item.title)
                          .font(.headline)
                          .foregroundStyle(.primary)
                        Text(item.detail)
                          .font(.caption)
                          .foregroundStyle(.secondary)
                          .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: template == item ? "checkmark.circle.fill" : "circle")
                          .foregroundStyle(template == item ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                      }
                      .padding(16)
                      .frame(width: 176, height: 164, alignment: .leading)
                      .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                      .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                          .stroke(template == item ? Color.primary : Color.clear, lineWidth: 1.5)
                      }
                    }
                    .buttonStyle(.plain)
                  }
                }
              }
              .scrollIndicators(.hidden)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
          }

          NavigationLink {
            SummaryAIModelPicker(selection: $aiModel)
          } label: {
            HStack(spacing: 12) {
              Image(systemName: "cpu")
                .frame(width: 28)
              VStack(alignment: .leading, spacing: 2) {
                Text("AIモデル")
                  .font(.headline)
                  .foregroundStyle(.primary)
                Text("推定コスト \(aiModel.costLabel) · 確定時だけ実行")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Text(aiModel.title)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
              Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
            }
          }
          .buttonStyle(.plain)
          .padding(.horizontal, 4)

          Button("生成") {
            model.generateSummary(
              meetingID,
              template: mode == .automatic ? .automatic : template,
              aiModel: aiModel
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .animation(.smooth, value: mode)
        .onChange(of: mode) { _, newValue in
          if newValue == .custom {
            selectedDetent = .large
          }
        }
      }
      .navigationTitle("要約を生成")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large], selection: $selectedDetent)
    .presentationDragIndicator(.visible)
  }

  private func generationChoice(
    mode candidate: SummaryGenerationMode,
    title: String,
    detail: String,
    symbol: String
  ) -> some View {
    Button {
      mode = candidate
    } label: {
      HStack(spacing: 14) {
        Image(systemName: symbol)
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
        Image(systemName: mode == candidate ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(mode == candidate ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
      }
      .padding(14)
      .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(mode == candidate ? .isSelected : [])
  }
}

private struct SummaryAIModelPicker: View {
  @Environment(\.dismiss) private var dismiss
  @Binding var selection: SummaryAIModel

  var body: some View {
    List {
      ForEach(SummaryAIModel.allCases) { model in
        Button {
          selection = model
          dismiss()
        } label: {
          HStack(spacing: 14) {
            Image(systemName: model == .economy ? "leaf" : model == .deep ? "brain.head.profile" : "cpu")
              .font(.title3)
              .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
              Text(model.title)
                .font(.headline)
                .foregroundStyle(.primary)
              Text(model.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text("コスト \(model.costLabel)")
              .font(.caption.weight(.medium))
              .foregroundStyle(.secondary)
            if selection == model {
              Image(systemName: "checkmark")
                .font(.body.bold())
                .foregroundStyle(.primary)
            }
          }
          .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == model ? .isSelected : [])
      }
    }
    .navigationTitle("AIモデルを選択")
    .navigationBarTitleDisplayMode(.inline)
  }
}

private enum SummaryGenerationMode {
  case automatic
  case custom
}
