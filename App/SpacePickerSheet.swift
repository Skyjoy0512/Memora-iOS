import SwiftUI

/// Files a record under a project, or under none.
struct SpacePickerSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var meetingID: UUID

  var body: some View {
    NavigationStack {
      List {
        Section {
          row(title: "未分類", symbol: "tray", isSelected: currentSpaceID == nil) {
            set(nil)
          }

          ForEach(model.spaces) { space in
            row(title: space.name, symbol: space.symbol, isSelected: currentSpaceID == space.id) {
              set(space.id)
            }
          }
        } footer: {
          Text("会議はどのプロジェクトにも入れないままにできます。")
        }
      }
      .navigationTitle("プロジェクト")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("閉じる") { dismiss() }
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

  private func set(_ spaceID: UUID?) {
    model.setSpace(spaceID, forMeeting: meetingID)
    dismiss()
  }
}
