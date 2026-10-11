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
        Text("仕事・活動はおすすめの順序にだけ使います。職業を選ばなくても、すべての記録・テンプレートを使えます。")
          .foregroundStyle(.secondary)
        if !selected.isEmpty {
          Picker("主な仕事・活動", selection: $model.occupationProfile.primaryOccupationID) {
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
    .onChange(of: model.occupationProfile.primaryOccupationID) { _, _ in
      model.occupationProfile.updatedAt = .now
    }
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
