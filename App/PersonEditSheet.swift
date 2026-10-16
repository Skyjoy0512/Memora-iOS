import SwiftUI

/// Edits one person: their name, a note, and merging a duplicate into them.
struct PersonEditSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var personID: UUID

  @State private var name = ""
  @State private var note = ""
  @State private var mergeTarget: Person?
  @State private var isMergeConfirmationPresented = false
  @State private var didLoad = false
  @State private var saveError = false

  private var person: Person? {
    model.person(id: personID)
  }

  private var otherPeople: [Person] {
    model.people.filter { $0.id != personID }
  }

  private var trimmedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    let allOptions = PersonSelectionOption.options(model.people)
    let mergeOptions = allOptions.filter { $0.id != personID }
    NavigationStack {
      Form {
        Section("名前") {
          TextField("名前", text: $name)
        }

        Section {
          TextField("メモ", text: $note, axis: .vertical)
            .lineLimit(1...5)
        } header: {
          Text("メモ")
        } footer: {
          Text("会社や関係など、思い出せることを書いておけます。")
        }

        Section {
          Menu {
            ForEach(mergeOptions) { option in
              Button(option.label) {
                mergeTarget = otherPeople.first { $0.id == option.id }
                isMergeConfirmationPresented = true
              }
            }
          } label: {
            Label("重複した相手と統合", icon: .arrowTriangleMerge)
          }
          .disabled(otherPeople.isEmpty)
        } footer: {
          if otherPeople.isEmpty {
            Text("統合できる相手がいません。")
          } else {
            Text("参加している記録、人物を指定したタスクとジャーナルの関連は、選んだ相手へ移ります。名前だけの関連は変更しません。記録は削除されません。")
          }
        }
      }
      .navigationTitle("人を編集")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("保存", icon: .checkmark) {
            if model.updatePerson(personID, name: trimmedName, note: note) { dismiss() }
            else { saveError = true }
          }
          .disabled(trimmedName.isEmpty)
        }
      }
      .alert("統合しますか？", isPresented: $isMergeConfirmationPresented) {
        Button("統合", role: .destructive) { merge() }
        Button("キャンセル", role: .cancel) { mergeTarget = nil }
      } message: {
        if let mergeTarget {
          let sourceLabel = allOptions.first { $0.id == personID }?.label ?? "この人"
          let targetLabel = allOptions.first { $0.id == mergeTarget.id }?.label ?? mergeTarget.name
          Text("「\(sourceLabel)」を「\(targetLabel)」に統合します。参加している会議\(model.meetingCount(forPerson: personID))件、人物を指定したタスクとジャーナルの関連を移します。名前だけの関連は変更しません。")
        }
      }
      .alert("保存できませんでした", isPresented: $saveError) {
        Button("閉じる", role: .cancel) {}
      } message: {
        Text("人物や保存先の状態を確認してください。入力内容は画面に残っています。")
      }
      .onAppear {
        guard !didLoad else { return }
        didLoad = true
        name = person?.name ?? ""
        note = person?.note ?? ""
      }
    }
  }

  private func merge() {
    guard let mergeTarget else { return }
    if model.mergePerson(personID, into: mergeTarget.id) {
      self.mergeTarget = nil
      dismiss()
    } else { saveError = true }
  }
}
