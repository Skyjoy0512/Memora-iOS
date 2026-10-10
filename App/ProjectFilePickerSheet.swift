import SwiftUI

struct ProjectFilePickerSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var spaceID: UUID
  @State private var selectedIDs: Set<UUID> = []
  @State private var query = ""

  var body: some View {
    let available = model.meetings.filter { $0.spaceID != spaceID }
    let matching = available.filter {
      query.isEmpty || $0.displayTitle.localizedStandardContains(query)
    }
    let selected = selectedIDs.intersection(Set(available.map(\.id)))
    let projectNames = Dictionary(uniqueKeysWithValues: model.spaces.map { ($0.id, $0.name) })

    NavigationStack {
      List {
        if let message = model.persistenceFailureMessage {
          Section {
            Label(message, icon: .exclamationmarkTriangle)
              .foregroundStyle(.red)
          }
        }
        Section {
          ForEach(matching) { meeting in
            Button {
              if !selectedIDs.insert(meeting.id).inserted { selectedIDs.remove(meeting.id) }
            } label: {
              HStack(spacing: 12) {
                Image(icon: selected.contains(meeting.id) ? .checkmarkCircleFill : .circle)
                  .foregroundStyle(selected.contains(meeting.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 5) {
                  Text(meeting.displayTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                  Text(meeting.spaceID.flatMap { projectNames[$0] } ?? "未分類")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
              }
              .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected.contains(meeting.id) ? [.isSelected] : [])
            .accessibilityHint("タップで移動するファイルを選択・解除します")
          }
        } footer: {
          Text("\(model.space(id: spaceID)?.name ?? "プロジェクト")へ移動します。元のプロジェクトや未分類の一覧からは非表示になります。")
        }
      }
      .overlay {
        if available.isEmpty {
          ContentUnavailableView("移動できるファイルがありません", icon: .folder, description: Text("このプロジェクトにまだ入っていないファイルがここに表示されます。"))
        } else if matching.isEmpty {
          ContentUnavailableView.search(text: query)
        }
      }
      .searchable(text: $query, prompt: "ファイル名で検索")
      .navigationTitle("既存ファイルを移動")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("移動（\(selected.count)件）") {
            if model.moveMeetings(selected, to: spaceID) { dismiss() }
          }
          .disabled(selected.isEmpty || model.space(id: spaceID) == nil || model.isRestoring)
        }
      }
    }
  }
}
