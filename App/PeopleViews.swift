import SwiftUI

/// A round initials badge for a person.
struct PersonAvatar: View {
  var name: String
  var size: CGFloat = 40

  var body: some View {
    Text(String(name.prefix(1)))
      .font(.system(size: size * 0.42, weight: .semibold))
      .foregroundStyle(.primary)
      .frame(width: size, height: size)
      .background(Color.primary.opacity(0.08), in: Circle())
      .accessibilityHidden(true)
  }
}

/// The people tagged across recordings, laid out like a contacts list.
struct PeopleListView: View {
  @Environment(MemoraModel.self) private var model

  var body: some View {
    Group {
      if model.people.isEmpty {
        ContentUnavailableView {
          Label("まだ人がいません", systemImage: "person.2")
        } description: {
          Text("会議に参加した人を連絡先から選ぶか、新しく作って記録にひもづけられます。")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List {
          ForEach(model.people) { person in
            NavigationLink(value: LibraryRoute.person(person.id)) {
              HStack(spacing: 12) {
                PersonAvatar(name: person.name)

                VStack(alignment: .leading, spacing: 2) {
                  Text(person.name)
                    .font(.body.weight(.semibold))
                  Text("\(model.meetingCount(forPerson: person.id))件の記録")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
              }
              .padding(.vertical, 4)
            }
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
      }
    }
    .hideBottomBarOnScroll()
  }
}

/// One person and the recordings they are tagged on.
struct PersonDetailView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var personID: UUID

  var body: some View {
    Group {
      if let person = model.person(id: personID) {
        List {
          Section {
            HStack(spacing: 14) {
              PersonAvatar(name: person.name, size: 54)
              Text(person.name)
                .font(.title2.bold())
            }
            .padding(.vertical, 4)
          }

          let meetings = model.meetings(withPerson: personID)
          if meetings.isEmpty {
            Section {
              Text("この人の記録はまだありません。")
                .foregroundStyle(.secondary)
            }
          } else {
            Section("記録") {
              ForEach(meetings) { meeting in
                NavigationLink(value: LibraryRoute.meeting(meeting.id)) {
                  MeetingRow(meeting: meeting, showsDisclosure: false)
                }
              }
            }
          }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button("削除", systemImage: "trash", role: .destructive) {
              model.deletePerson(personID)
              dismiss()
            }
          }
        }
      } else {
        ContentUnavailableView("人が見つかりません", systemImage: "person.slash")
      }
    }
  }
}
