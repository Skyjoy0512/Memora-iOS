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
            ForEach(otherPeople) { other in
              Button(other.name) {
                mergeTarget = other
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
            Text("参加している記録とタスクの担当は、選んだ相手の方へ移ります。記録は削除されません。")
          }
        }
      }
      .navigationTitle("人を編集")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            model.updatePerson(personID, name: trimmedName, note: note)
            dismiss()
          }
          .disabled(trimmedName.isEmpty)
        }
      }
      .alert("統合しますか？", isPresented: $isMergeConfirmationPresented) {
        Button("統合", role: .destructive) { merge() }
        Button("キャンセル", role: .cancel) { mergeTarget = nil }
      } message: {
        if let mergeTarget {
          Text("「\(person?.name ?? "この人")」を「\(mergeTarget.name)」に統合します。参加している記録\(model.meetingCount(forPerson: personID))件とタスクの担当が「\(mergeTarget.name)」に移ります。")
        }
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
    model.mergePerson(personID, into: mergeTarget.id)
    self.mergeTarget = nil
    dismiss()
  }
}
