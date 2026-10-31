import SwiftUI

struct CommunitySubmissionPicker: View {
  @Environment(MemoraModel.self) private var model
  @State private var selectedSkill: MemoraSkill?
  @State private var selectedTemplate: SummaryMarketTemplate?
  var body: some View {
    List {
      if model.customSkills.isEmpty && model.customTemplates.isEmpty {
        ContentUnavailableView("公開する項目を作りましょう", icon: .squareAndPencil,
          description: Text("作成したスキルや要約テンプレートを選んで投稿できます。"))
      }
      Section("マイスキル") {
        ForEach(model.customSkills) { skill in Button(skill.name) { selectedSkill = skill } }
      }
      Section("マイテンプレート") {
        ForEach(model.customTemplates) { template in Button(template.title) { selectedTemplate = template } }
      }
    }
    .navigationTitle("投稿する項目").navigationBarTitleDisplayMode(.inline)
    .sheet(item: $selectedSkill) { CommunityPublishSheet(definition: .init(skill: $0)) }
    .sheet(item: $selectedTemplate) { CommunityPublishSheet(definition: .init(template: $0)) }
  }
}
