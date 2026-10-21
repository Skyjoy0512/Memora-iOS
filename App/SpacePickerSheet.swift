import SwiftUI

/// Files a record under a project, or under none.
struct SpacePickerSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var meetingID: UUID

  var body: some View {
    NavigationStack {
      MemoraList {
        if let message = model.persistenceFailureMessage {
          Section {
            Label(message, icon: .exclamationmarkTriangle)
              .foregroundStyle(.red)
          }
        }
        Section {
          row(title: "未分類", symbol: .tray, isSelected: currentSpaceID == nil) {
            set(nil)
          }

          ForEach(model.spaces) { space in
            row(title: space.name, symbol: space.icon, isSelected: currentSpaceID == space.id) {
              set(space.id)
            }
          }
        } footer: {
          Text("移動したファイルは移動先だけに表示されます。未分類を選ぶと、通常のファイル一覧に戻ります。")
        }
      }
      .navigationTitle("プロジェクト")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  private var currentSpaceID: UUID? {
    model.meeting(id: meetingID)?.spaceID
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

  private func set(_ spaceID: UUID?) {
    if model.setSpace(spaceID, forMeeting: meetingID) {
      InteractionFeedback.shared.send(.success)
      dismiss()
    } else {
      InteractionFeedback.shared.send(.error)
    }
  }
}
