import SwiftUI

struct TaskAssigneeFields: View {
  var people: [Person]
  @Binding var name: String
  @Binding var personID: UUID?
  @Binding var ownedByMe: Bool

  var body: some View {
    let options = PersonSelectionOption.options(people)
    let selected = people.first { $0.id == personID }
    Group {
      Toggle("自分のタスク", isOn: $ownedByMe)
      if !ownedByMe {
        if !options.isEmpty || personID != nil {
          Picker("担当する人物", selection: $personID) {
            Text("人物を指定しない").tag(UUID?.none)
            ForEach(options) { option in Text(option.label).tag(UUID?.some(option.id)) }
            if let personID, selected == nil {
              Text("削除された人物（\(personID.uuidString.prefix(8))）").tag(UUID?.some(personID))
            }
          }
          .pickerStyle(.navigationLink)
        }
        if personID == nil {
          TextField("担当名（任意・本人未確認）", text: $name)
        } else if selected == nil {
          Text("以前の人物との関連を保持しています。必要なら人物を選び直すか、指定を解除してください。")
            .font(.footnote).foregroundStyle(.secondary)
        }
      }
    }
    .onChange(of: personID) { _, id in
      if let person = people.first(where: { $0.id == id }) { name = person.name }
    }
    .onChange(of: ownedByMe) { _, owns in if owns { personID = nil } }
  }
}
