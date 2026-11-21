import SwiftUI

struct AIChatModelSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          modelRow("Auto", detail: "設定したAIエンジンに合わせて選択", id: nil)
          ForEach(model.registeredLLMs.models) { registered in
            let isReady = EngineAvailability.hasKey(registered.provider.keychainAccount)
            modelRow(registered.name, detail: isReady ? registered.provider.label : "\(registered.provider.label)（APIキー未設定）",
              id: registered.id, isReady: isReady)
          }
        } footer: {
          Text("次のメッセージから選択したモデルを使います。")
        }
        Section {
          NavigationLink("モデルを管理", destination: RegisteredLLMsView())
            .listRowBackground(MemoraPalette.elevated)
        }
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .background(MemoraPalette.secondaryBackground)
      .navigationTitle("モデルを選択")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }

  private func modelRow(_ title: String, detail: String, id: UUID?, isReady: Bool = true) -> some View {
    Button {
      if let id {
        guard let current = model.registeredLLMs.models.first(where: { $0.id == id }),
              EngineAvailability.hasKey(current.provider.keychainAccount) else { return }
      }
      model.registeredLLMs.select(id)
      dismiss()
    } label: {
      HStack(spacing: MemoraSpacing.md) {
        VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
          Text(title).font(.body).foregroundStyle(.primary)
          Text(detail).font(.footnote).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
        if model.registeredLLMs.selectedID == id {
          Image(icon: .checkmark, size: 20)
            .foregroundStyle(MemoraPalette.textPrimary)
            .accessibilityHidden(true)
        }
      }.frame(minHeight: 52).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!isReady)
    .listRowBackground(MemoraPalette.elevated)
    .accessibilityAddTraits(model.registeredLLMs.selectedID == id ? .isSelected : [])
  }
}
