import SwiftUI

/// Everyone in the records, most recently met first. Each opens what the
/// records hold about them.
struct PeopleView: View {
  @Environment(MemoraModel.self) private var model
  @State private var isManaging = false
  @State private var query = ""
  @State private var isSearching = false

  var body: some View {
    let isAwaitingQuery = isSearching && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let people = isAwaitingQuery ? [] : sortedPeople.filter {
      CollectionSearch.matches(query, fields: [$0.name, $0.note ?? ""])
    }

    MemoraList {
      ForEach(people) { person in
        NavigationLink(value: LibraryRoute.person(person.id)) {
          HStack(spacing: 12) {
            PersonAvatar(name: person.name, size: 44, photoData: person.photoData)
            VStack(alignment: .leading, spacing: 2) {
              Text(person.name)
                .font(.body.weight(.medium))
              Text(caption(for: person))
                .font(MemoraTypography.metadata)
                .foregroundStyle(MemoraPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          .padding(.vertical, MemoraSpacing.xxs)
          .frame(maxWidth: .infinity, minHeight: ProjectLayout.minimumRowHeight, alignment: .leading)
          .accessibilityElement(children: .combine)
        }
      }
    }
    .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
    .overlay(alignment: .top) {
      if isSearching && people.isEmpty {
        CollectionSearchState(title: isAwaitingQuery ? "人物を検索" : "見つかりません",
          message: isAwaitingQuery ? "名前やメモから探せます。" : "名前やメモの一部で検索してください。")
          .accessibilityIdentifier("people.search.state")
      } else if model.people.isEmpty {
        ScrollView {
          MemoraEmptyState(icon: .person2, title: "まだ人がいません",
            message: "会議に参加した人を登録すると、話したことや約束がここにまとまります。",
            actionTitle: "人を追加", actionIcon: .personBadgePlus) { isManaging = true }
            .padding(.top, MemoraSpacing.section)
            .padding(.bottom, model.bottomContentClearance)
        }
      }
    }
    .navigationTitle("人物")
    .toolbarSearch(text: $query, isPresented: $isSearching, prompt: "名前・メモを検索")
    .toolbar {
      ToolbarActionItem {
        ToolbarIconButton("人物を検索", icon: .magnifyingglass) { isSearching = true }
      }
      ToolbarActionGap()
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
    return "会議\(count)件 · 最後に会った日 \(MemoraFormat.documentDate(last))"
  }
}
