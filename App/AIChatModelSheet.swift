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
            modelRow(registered.name, detail: registered.provider.label, id: registered.id)
          }
        } footer: {
          Text("次のメッセージから選択したモデルを使います。")
        }
        Section {
          NavigationLink("モデルを管理", destination: RegisteredLLMsView())
            .listRowBackground(MemoraPalette.elevated)
        }
      }
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

  private func modelRow(_ title: String, detail: String, id: UUID?) -> some View {
    Button {
      model.registeredLLMs.select(id)
      dismiss()
    } label: {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 5) {
          Text(title).font(.body).foregroundStyle(.primary)
          Text(detail).font(.footnote).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
        if model.registeredLLMs.selectedID == id {
          Image(icon: .checkmark, size: 20).foregroundStyle(MemoraPalette.focus)
        }
      }.frame(minHeight: 52).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .listRowBackground(MemoraPalette.elevated)
    .accessibilityAddTraits(model.registeredLLMs.selectedID == id ? .isSelected : [])
  }
}
