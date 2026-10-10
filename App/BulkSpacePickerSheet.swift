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
        if let message = model.persistenceFailureMessage {
          Section {
            Label(message, icon: .exclamationmarkTriangle)
              .foregroundStyle(.red)
          }
        }
        Section {
          row(title: "未分類", symbol: .tray, isSelected: isCurrentDestination(nil)) {
            move(to: nil)
          }

          ForEach(model.spaces) { space in
            row(title: space.name, symbol: space.icon, isSelected: isCurrentDestination(space.id)) {
              move(to: space.id)
            }
          }
        } footer: {
          Text("\(meetingIDs.count)件を移動します。保存に成功すると、移動元の一覧から非表示になります。")
        }
      }
      .navigationTitle("プロジェクトへ移動")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  /// The project every selected record shares, so the current one is marked.
  /// Mixed selections show none as chosen, so a tap moves all of them.
  private func isCurrentDestination(_ spaceID: UUID?) -> Bool {
    !meetingIDs.isEmpty && meetingIDs.allSatisfy { id in
      guard let meeting = model.meeting(id: id) else { return false }
      return meeting.spaceID == spaceID
    }
  }

  private func move(to spaceID: UUID?) {
    guard model.moveMeetings(meetingIDs, to: spaceID) else {
      InteractionFeedback.shared.send(.error)
      return
    }
    InteractionFeedback.shared.send(.success)
    onMove()
    dismiss()
  }

  private func row(
    title: String,
    symbol: MemoraIcon,
    isSelected: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(icon: symbol)
          .frame(width: 24)
          .foregroundStyle(.primary)

        Text(title)
          .foregroundStyle(.primary)

        Spacer()

        if isSelected {
          Image(icon: .checkmark)
            .foregroundStyle(.primary)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }
}
