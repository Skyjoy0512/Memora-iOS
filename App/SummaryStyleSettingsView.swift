import SwiftUI

struct SummaryStyleSettingsView: View {
  @Environment(MemoraModel.self) private var model

  var body: some View {
    @Bindable var model = model
    Form {
      Section {
        Picker("要約方法", selection: $model.summaryPreferences.method) {
          ForEach(SummaryPreferences.Method.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        if model.summaryPreferences.method == .fixed {
          Picker("既定のテンプレート", selection: Binding {
            model.defaultTemplateID ?? SummaryTemplateChoice.standard.id
          } set: { model.defaultTemplateID = $0 == SummaryTemplateChoice.standard.id ? nil : $0 }) {
            ForEach(model.allSummaryChoices) { Text($0.title).tag($0.id) }
          }
        }
      } footer: {
        Text("既存ユーザーは以前の要約方法を維持します。設定を変えても過去の要約は変わりません。")
      }
      Section {
        Picker("要約の詳しさ", selection: $model.summaryPreferences.length) {
          ForEach(SummaryLength.allCases) { Text($0.title).tag($0) }
        }
        Picker("表示順", selection: $model.summaryPreferences.displayOrder) {
          ForEach(SummaryPreferences.DisplayOrder.allCases, id: \.self) { Text($0.title).tag($0) }
        }
      } footer: { Text("原音声と文字起こしは変更しません。次に生成する要約から適用します。") }
      NavigationLink("すべてのテンプレート") { SummaryTemplateMarketplaceView() }
    }
    .navigationTitle("要約スタイル")
    .memoraBackButton()
  }
}
