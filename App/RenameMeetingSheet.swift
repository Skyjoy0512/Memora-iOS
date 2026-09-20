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
      Form {
        TextField("会議名", text: $title)
      }
      .navigationTitle("名前を変更")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") {
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
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
