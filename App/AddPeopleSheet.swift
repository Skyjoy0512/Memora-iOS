import SwiftUI

/// Tags people on a recording, picking from the address book or creating them
/// here.
struct AddPeopleSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var meetingID: UUID

  @State private var newName = ""
  @State private var contacts: [ContactSuggestion] = []
  @State private var isLoadingContacts = true
  @State private var contactAccessDenied = false

  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack {
            TextField("名前を入力", text: $newName)
              .onSubmit(addNew)

            Button("追加") { addNew() }
              .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        } header: {
          Text("新規作成")
        }

        if !model.people.isEmpty {
          Section("登録済み") {
            ForEach(model.people) { person in
              row(title: person.name, isOn: isParticipant(person.id)) {
                model.toggleParticipant(personID: person.id, meeting: meetingID)
              }
            }
          }
        }

        Section {
          if isLoadingContacts {
            HStack(spacing: 10) {
              ProgressView()
              Text("連絡先を読み込んでいます")
                .foregroundStyle(.secondary)
            }
          } else if contactAccessDenied {
            Text("設定で連絡先へのアクセスを許可すると、連絡先から選べます。")
              .font(.footnote)
              .foregroundStyle(.secondary)
          } else if contacts.isEmpty {
            Text("連絡先が見つかりません。")
              .font(.footnote)
              .foregroundStyle(.secondary)
          } else {
            ForEach(contacts) { contact in
              row(title: contact.name, isOn: isContactParticipant(contact)) {
                toggle(contact)
              }
            }
          }
        } header: {
          Text("連絡先")
        }
      }
      .navigationTitle("参加者")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("完了") { dismiss() }
        }
      }
      .task { await loadContacts() }
    }
  }

  private func row(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack {
        Text(title)
          .foregroundStyle(.primary)
        Spacer()
        if isOn {
          Image(systemName: "checkmark")
            .font(.body.weight(.semibold))
            .foregroundStyle(.tint)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func isParticipant(_ personID: UUID) -> Bool {
    (model.meeting(id: meetingID)?.participantIDs ?? []).contains(personID)
  }

  private func isContactParticipant(_ contact: ContactSuggestion) -> Bool {
    model.people.contains { person in
      person.contactIdentifier == contact.id && isParticipant(person.id)
    }
  }

  private func toggle(_ contact: ContactSuggestion) {
    guard let person = model.addPerson(name: contact.name, contactIdentifier: contact.id) else { return }
    model.toggleParticipant(personID: person.id, meeting: meetingID)
  }

  private func addNew() {
    guard let person = model.addPerson(name: newName) else { return }
    newName = ""
    if !isParticipant(person.id) {
      model.toggleParticipant(personID: person.id, meeting: meetingID)
    }
  }

  private func loadContacts() async {
    guard await ContactsService.requestAccess() else {
      contactAccessDenied = true
      isLoadingContacts = false
      return
    }
    contacts = await ContactsService.fetchContacts()
    isLoadingContacts = false
  }
}
