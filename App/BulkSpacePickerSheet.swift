import SwiftUI

/// Files several records under one project at once, or under none.
struct BulkSpacePickerSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var meetingIDs: Set<UUID>
  /// Called after the move lands, so the caller can leave selection mode.
  var onMove: () -> Void

  var body: some View {
    NavigationStack {
      List {
        Section {
          row(title: "未分類", symbol: "tray", isSelected: sharedSpaceID == nil) {
            move(to: nil)
          }

          ForEach(model.spaces) { space in
            row(title: space.name, symbol: space.symbol, isSelected: sharedSpaceID == space.id) {
              move(to: space.id)
            }
          }
        } footer: {
          Text("\(meetingIDs.count)件のファイルをまとめて移動します。")
        }
      }
      .navigationTitle("プロジェクトへ移動")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  /// The project every selected record shares, so the current one is marked.
  /// Mixed selections show none as chosen, so a tap moves all of them.
  private var sharedSpaceID: UUID? {
    let spaces = meetingIDs.map { model.meeting(id: $0)?.spaceID }
    guard let first = spaces.first, spaces.allSatisfy({ $0 == first }) else { return nil }
    return first
  }

  private func move(to spaceID: UUID?) {
    model.moveMeetings(meetingIDs, to: spaceID)
    onMove()
    dismiss()
  }

  private func row(
    title: String,
    symbol: String,
    isSelected: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: symbol)
          .frame(width: 24)
          .foregroundStyle(.secondary)

        Text(title)
          .foregroundStyle(.primary)

        Spacer()

        if isSelected {
          Image(systemName: "checkmark")
            .foregroundStyle(.tint)
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }
}
