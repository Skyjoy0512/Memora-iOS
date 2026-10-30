import SwiftUI

/// The models for the chosen provider: suggestions first, then the list the
/// saved key can actually call, and a free-form id for anything newer.
struct LLMModelPickerView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var available: [String] = []
  @State private var isLoading = false
  @State private var loadError: String?
  @State private var customID = ""
  @State private var query = ""

  private var provider: LLMProvider { model.aiProvider }
  private var hasKey: Bool { EngineAvailability.hasKey(provider.keychainAccount) }

  /// Loaded ids that are not already suggested, filtered by the search text.
  private var otherModels: [String] {
    let suggested = Set(provider.suggestedModels.map(\.id))
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    return available.filter { id in
      !suggested.contains(id) && (trimmed.isEmpty || id.localizedCaseInsensitiveContains(trimmed))
    }
  }

  var body: some View {
    MemoraForm {
      Section {
        ForEach(provider.suggestedModels) { option in
          row(id: option.id, title: option.name, detail: option.detail.map { "\($0) · \(option.id)" } ?? option.id)
        }
      } header: {
        HStack(spacing: 8) {
          ProviderLogo(provider: provider, size: 20)
          Text("おすすめ")
        }
      } footer: {
        if !available.isEmpty,
           !provider.suggestedModels.contains(where: { available.contains($0.id) }) {
          Text("おすすめのモデルがこのキーの一覧にありません。下の一覧から選んでください。")
        }
      }

      Section {
        if isLoading {
          HStack(spacing: 10) {
            ProgressView()
            Text("モデル一覧を読み込み中…")
              .foregroundStyle(.secondary)
          }
        } else if let loadError {
          Label(loadError, icon: .exclamationmarkTriangle)
            .foregroundStyle(.secondary)
        } else if !hasKey {
          Text("APIキーを保存すると、そのキーで使えるモデルを一覧できます。")
            .foregroundStyle(.secondary)
        }

        ForEach(otherModels, id: \.self) { id in
          row(id: id, title: id, detail: nil)
        }

        if hasKey {
          Button("一覧を更新", icon: .arrowClockwise) {
            Task { await load() }
          }
          .disabled(isLoading)
        }
      } header: {
        Text("このキーで使えるモデル")
      }

      Section {
        HStack {
          TextField("モデルID（例: \(provider.defaultModelID)）", text: $customID)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit(useCustomID)
          Button("使う", action: useCustomID)
            .disabled(customID.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      } header: {
        Text("IDを直接入力")
      } footer: {
        Text("新しいモデルが出たときは、各社のドキュメントにあるモデルIDをそのまま入力できます。")
      }
    }
    .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "モデルを検索")
    .navigationTitle("\(provider.label)のモデル")
    .memoraBackButton()
    .task { await load() }
  }

  private func row(id: String, title: String, detail: String?) -> some View {
    Button {
      model.aiModelID = id
      model.registeredLLMs.register(provider: provider, modelID: id, name: title)
      dismiss()
    } label: {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .foregroundStyle(.primary)
          if let detail {
            Text(detail)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: 8)
        if id == model.aiModelID {
          Image(icon: .checkmark, size: 17)
            .foregroundStyle(.primary)
        }
      }
      .contentShape(Rectangle())
    }
    .accessibilityAddTraits(id == model.aiModelID ? .isSelected : [])
  }

  private func useCustomID() {
    let id = customID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else { return }
    model.aiModelID = id
    model.registeredLLMs.register(provider: provider, modelID: id, name: id)
    dismiss()
  }

  private func load() async {
    guard hasKey else { return }
    isLoading = true
    loadError = nil
    defer { isLoading = false }
    do {
      available = try await LLMModelListService.fetchModels(for: provider)
    } catch let failure as AIAnswerFailure {
      loadError = failure == .unauthorized ? "キーが受け付けられませんでした。キーを確認してください。" : "一覧を読み込めませんでした。"
    } catch {
      loadError = "一覧を読み込めませんでした。接続を確認してください。"
    }
  }
}
