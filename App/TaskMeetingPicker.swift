import SwiftUI

struct TaskMeetingPicker: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Binding var selection: UUID?
  @State private var query = ""

  var body: some View {
    let matches = model.meetings.filter { CollectionSearch.matches(query, fields: [$0.displayTitle]) }
    NavigationStack {
      List {
        choice("なし", id: nil)
        ForEach(matches) { meeting in
          choice(meeting.displayTitle, id: meeting.id)
        }
        if !query.isEmpty && matches.isEmpty {
          Text("一致する会議はありません").foregroundStyle(.secondary)
        }
      }
      .searchable(text: $query, prompt: "会議名を検索")
      .navigationTitle("元の会議")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
        }
      }
    }
  }

  private func choice(_ title: String, id: UUID?) -> some View {
    Button {
      selection = id
      dismiss()
    } label: {
      HStack {
        Text(title).foregroundStyle(.primary).multilineTextAlignment(.leading)
        Spacer()
        if selection == id { Image(icon: .checkmark).accessibilityHidden(true) }
      }
      .frame(maxWidth: .infinity, minHeight: 44)
      .contentShape(Rectangle())
    }
    .accessibilityAddTraits(selection == id ? [.isSelected] : [])
  }
}
