import SwiftUI

/// Everyone in the records, most recently met first. Each opens what the
/// records hold about them.
struct PeopleView: View {
  @Environment(MemoraModel.self) private var model
  @State private var isManaging = false

  var body: some View {
    let people = sortedPeople

    List {
      ForEach(people) { person in
        NavigationLink(value: LibraryRoute.person(person.id)) {
          HStack(spacing: 12) {
            PersonAvatar(name: person.name, size: 44, photoData: person.photoData)
            VStack(alignment: .leading, spacing: 2) {
              Text(person.name)
                .font(.body.weight(.semibold))
              Text(caption(for: person))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          .padding(.vertical, MemoraSpacing.xxs)
          .accessibilityElement(children: .combine)
        }
      }
    }
    .listStyle(.plain)
    .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
    .overlay {
      if people.isEmpty {
        ContentUnavailableView {
          Label("まだ人がいません", icon: .person2)
        } description: {
          Text("会議に参加した人を登録すると、その人と話したことや約束がここにまとまります。")
        } actions: {
          Button("人を追加") { isManaging = true }
        }
      }
    }
    .navigationTitle("人物")
    .toolbar {
      ToolbarActionItem {
        ToolbarIconButton("人を追加・編集", icon: .personBadgePlus) { isManaging = true }
          .labelStyle(.iconOnly)
      }
    }
    .sheet(isPresented: $isManaging) {
      PeopleManagerSheet()
    }
  }

  /// Met most recently first; people never met keep their added order after.
  private var sortedPeople: [Person] {
    model.people.enumerated()
      .sorted { lhs, rhs in
        let left = model.meetings(withPerson: lhs.element.id).first?.createdAt
        let right = model.meetings(withPerson: rhs.element.id).first?.createdAt
        switch (left, right) {
        case let (left?, right?): return left > right
        case (.some, nil): return true
        case (nil, .some): return false
        case (nil, nil): return lhs.offset < rhs.offset
        }
      }
      .map(\.element)
  }

  private func caption(for person: Person) -> String {
    let count = model.meetingCount(forPerson: person.id)
    guard let last = model.meetings(withPerson: person.id).first?.createdAt else {
      return person.note ?? "記録はまだありません"
    }
    return "会議\(count)件 · 最後に会った日 \(last.formatted(date: .abbreviated, time: .omitted))"
  }
}
