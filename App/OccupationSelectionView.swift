import SwiftUI

struct OccupationSelectionView: View {
  @Environment(MemoraModel.self) private var model
  @State private var query = ""

  var body: some View {
    @Bindable var model = model
    let matching = OccupationCatalog.matching(query)
    let selected = model.occupationProfile.orderedIDs.compactMap { OccupationCatalog.occupation($0) }

    List {
      Section {
        Text("主な仕事・活動に合う要約テンプレートを選びます。手動で指定した形式は優先し、AIにおまかせなら会議や休日の内容にも合わせます。")
          .foregroundStyle(.secondary)
        if !selected.isEmpty {
          Picker("主な仕事・活動", selection: Binding {
            model.occupationProfile.primaryOccupationID
          } set: { model.setPrimaryOccupation($0) }) {
            ForEach(selected) { occupation in
              Text(occupation.title).tag(Optional(occupation.id))
            }
          }
          .pickerStyle(.menu)
          ForEach(selected) { occupation in
            HStack {
              Text(occupation.title)
              Spacer()
              Button("選択を外す", icon: .xmark) { model.setOccupation(occupation.id, selected: false) }
                .labelStyle(.iconOnly)
                .accessibilityLabel("\(occupation.title)の選択を外す")
            }
          }
        }
      } header: { Text("選択済み") }

      Section {
        LabeledContent(model.followsOccupationSummaryTemplates ? "基本のテンプレート" : "手動指定のテンプレート",
                       value: model.defaultSummaryChoice.title)
        if !model.followsOccupationSummaryTemplates {
          Button("仕事・活動に合う形式に切り替える") { model.useOccupationSummaryTemplates() }
        }
        NavigationLink("要約スタイルを調整") { SummaryStyleSettingsView() }
      } header: { Text("要約テンプレート") } footer: {
        Text(model.followsOccupationSummaryTemplates
          ? "職業を選ぶだけで基本の形式が変わります。用途・記録内容を優先し、過去の要約は変更しません。"
          : "手動で選んだ形式を優先しています。職業を変えても、この指定は上書きしません。")
      }

      ForEach(OccupationCatalog.categories) { category in
        let items = matching.filter { $0.categoryID == category.id }
        if !items.isEmpty {
          Section {
            ForEach(items) { occupation in
              Toggle(occupation.title, isOn: Binding {
                model.occupationProfile.selectedOccupationIDs.contains(occupation.id)
              } set: { model.setOccupation(occupation.id, selected: $0) })
            }
          } header: { Label(category.title, icon: category.icon) }
        }
      }
      Section("その他") {
        TextField("仕事・活動を自由に入力", text: $model.occupationProfile.customOccupationName)
          .onChange(of: model.occupationProfile.customOccupationName) { _, _ in
            model.occupationProfile.updatedAt = .now
          }
      }
    }
    .navigationTitle("仕事・活動")
    .memoraBackButton()
    .searchable(text: $query, prompt: "仕事を検索")
    .sensoryFeedback(.selection, trigger: model.occupationProfile.selectedOccupationIDs)
    .overlay {
      if !query.isEmpty && matching.isEmpty {
        ContentUnavailableView.search(text: query)
          .allowsHitTesting(false)
      }
    }
  }
}
