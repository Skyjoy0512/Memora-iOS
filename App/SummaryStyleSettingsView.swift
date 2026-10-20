import SwiftUI

struct SummaryStyleSettingsView: View {
  @Environment(MemoraModel.self) private var model
  @AppStorage(MemoraModel.autoSummaryAfterTranscriptionKey) private var autoSummaryAfterTranscription = false

  var body: some View {
    @Bindable var model = model
    MemoraForm {
      Section {
        Toggle("仕事・活動に合わせる", isOn: Binding {
          model.followsOccupationSummaryTemplates
        } set: { follows in
          if follows { model.useOccupationSummaryTemplates() }
          else { model.setDefaultSummaryTemplate(model.defaultSummaryChoice.id) }
        })
        LabeledContent("基本のテンプレート", value: model.defaultSummaryChoice.title)
        NavigationLink {
          OccupationSelectionView()
        } label: {
          LabeledContent("仕事・活動", value: model.occupationSummary)
        }
      } footer: {
        Text("オンなら主な仕事・活動に合う形式を選びます。AIにおまかせでは、用途と記録内容を優先します。")
      }
      Section {
        Picker("要約方法", selection: $model.summaryPreferences.method) {
          ForEach(SummaryPreferences.Method.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        if model.summaryPreferences.method == .fixed {
          Picker("既定のテンプレート", selection: Binding {
            model.defaultSummaryChoice.id
          } set: { model.setDefaultSummaryTemplate($0) }) {
            ForEach(model.allSummaryChoices) { Text($0.title).tag($0.id) }
          }
        }
      } footer: {
        Text("テンプレートを手動で選ぶと、その形式を優先します。設定を変えても過去の要約は変わりません。")
      }
      Section {
        Toggle("文字起こし後に要約を自動作成", isOn: $autoSummaryAfterTranscription)
      } footer: {
        Text("オンにすると、文字起こしが終わった記録の要約をバックグラウンドで作成します。クラウドAIは、その記録に外部送信の許可がある場合だけ使います。")
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
