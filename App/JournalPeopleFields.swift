import SwiftUI

struct JournalPeopleFields: View {
  var people: [Person]
  var retainedIDs: Set<UUID> = []
  @Binding var selection: Set<UUID>

  var body: some View {
    let options = PersonSelectionOption.options(people)
    let missing = selection.union(retainedIDs).subtracting(Set(options.map(\.id))).sorted { $0.uuidString < $1.uuidString }
    Section {
      NavigationLink {
        MemoraList {
          ForEach(options) { option in
            Toggle(option.label, isOn: binding(for: option.id))
          }
          if !missing.isEmpty {
            Section {
              ForEach(missing, id: \.self) { id in
                Toggle("削除済みの人物（ID \(id.uuidString)）", isOn: binding(for: id))
              }
            } footer: {
              Text("関連を残すか解除できます。同じ名前の新しい人物へ自動では移しません。")
            }
          }
          if options.isEmpty && missing.isEmpty {
            Text("登録された人物はまだいません。サイドメニューの「人物」から追加できます。")
              .foregroundStyle(.secondary)
          }
        }
        .navigationTitle("関連する人物")
        .navigationBarTitleDisplayMode(.inline)
      } label: {
        HStack {
          Text("関連する人物")
          Spacer()
          Text(selection.isEmpty ? "指定なし" : "\(selection.count)人")
            .foregroundStyle(.secondary)
        }
      }
      ForEach(options.filter { selection.contains($0.id) }) { option in
        Text(option.label).font(.subheadline).foregroundStyle(.secondary)
      }
      if !selection.intersection(Set(missing)).isEmpty {
        Text("削除済みの人物との関連が\(selection.intersection(Set(missing)).count)件あります。")
          .font(.subheadline).foregroundStyle(.secondary)
      }
    } footer: {
      Text("選んだ人物の記録として表示します。本人の発言や参加を確定するものではありません。関連を変更すると、この記録の外部送信許可は解除されます。")
    }
  }

  private func binding(for id: UUID) -> Binding<Bool> {
    Binding { selection.contains(id) } set: { selected in
      if selected { selection.insert(id) } else { selection.remove(id) }
    }
  }
}
