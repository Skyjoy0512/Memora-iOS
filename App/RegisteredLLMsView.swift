import SwiftUI

struct RegisteredLLMsView: View {
  @Environment(MemoraModel.self) private var model
  @State private var editing: RegisteredLLM?

  var body: some View {
    List {
      Section {
        ForEach(model.registeredLLMs.models) { registered in
          Button { editing = registered } label: {
            HStack(spacing: 12) {
              ProviderLogo(provider: registered.provider, size: 28)
              VStack(alignment: .leading, spacing: 4) {
                Text(registered.name).foregroundStyle(.primary)
                Text("\(registered.provider.label) · \(registered.modelID)")
                  .font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Image(icon: .pencil).foregroundStyle(.primary)
            }
          }
          .swipeActions {
            Button("登録を削除", icon: .trash, role: .destructive) {
              model.registeredLLMs.remove(registered.id)
            }
          }
        }
        Button("モデルを追加", icon: .plus) {
          editing = RegisteredLLM(provider: model.aiProvider, modelID: "", name: "")
        }
      } footer: {
        Text("登録したモデルだけがAsk AIの手動選択に表示されます。選択中の登録を削除するとAutoに戻ります。APIキーと会話は削除しません。")
      }
      Section("Auto") {
        Text("Autoは「AI整理」で設定したエンジンに従います。エンジンが自動の場合は対応端末のApple Foundation Modelsを使います。クラウドを設定した場合は、そのプロバイダーとモデルを使います。")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }
    .navigationTitle("登録済みモデル")
    .memoraBackButton()
    .sheet(item: $editing) { RegisteredLLMEditor(draft: $0) }
  }
}
