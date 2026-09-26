import SwiftUI

/// The short-lived offer to take a deletion back. It sits above the tab bar and
/// composer while the model keeps the action; the countdown lives in the model,
/// so a toast that is replaced can never leave a stale action behind.
struct UndoToast: View {
  @Environment(MemoraModel.self) private var model
  var action: UndoAction

  var body: some View {
    HStack(spacing: 12) {
      Text(action.message)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.primary)
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)

      Button("取り消す") {
        model.performPendingUndo()
      }
      .font(.subheadline.weight(.semibold))
      .accessibilityHint("削除を取り消します")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .memoraGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .onAppear {
      AccessibilityNotification.Announcement(action.message).post()
    }
  }
}
