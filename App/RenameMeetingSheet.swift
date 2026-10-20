import SwiftUI

struct RenameMeetingSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var meeting: Meeting
  @State private var title: String

  init(meeting: Meeting) {
    self.meeting = meeting
    _title = State(initialValue: meeting.title)
  }

  var body: some View {
    NavigationStack {
      MemoraForm {
        TextField("会議名", text: $title)
      }
      .navigationTitle("名前を変更")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) {
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("保存", icon: .checkmark) {
            model.renameMeeting(meeting.id, title: title)
            dismiss()
          }
          .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
    .presentationDetents([.medium])
  }
}
