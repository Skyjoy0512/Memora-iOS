import SwiftUI

/// Corrects one speaker name, either for the line that was tapped or for every
/// line that shares the speaker. Registered people can be picked by name, which
/// also tags them on the recording.
struct SpeakerEditSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var meetingID: UUID
  var segment: TranscriptSegment
  @State private var name: String
  @State private var appliesToAllSegments = true
  /// The registered person chosen by name, added to the recording only when the
  /// change is saved, so cancelling leaves the participants as they were.
  @State private var selectedPersonID: UUID?
  @State private var isSaving = false

  init(meetingID: UUID, segment: TranscriptSegment) {
    self.meetingID = meetingID
    self.segment = segment
    _name = State(initialValue: segment.speaker)
    _appliesToAllSegments = State(initialValue: segment.speakerID != nil || segment.speakerIsCertain)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("話者") {
          TextField("名前", text: $name)
            .textInputAutocapitalization(.never)
          Button("自分の発言として確認", icon: .person) { name = "自分" }
          Text("手動のラベル変更です。声の特徴量は登録・更新しません。")
            .font(.footnote).foregroundStyle(.secondary)
        }

        Section {
          Toggle("この話者のすべての発言に変更", isOn: $appliesToAllSegments)
            .disabled(segment.speakerID == nil && !segment.speakerIsCertain)
        }

        if !model.people.isEmpty {
          Section("登録済みの人") {
            ForEach(model.people) { person in
              Button {
                name = person.name
                selectedPersonID = person.id
              } label: {
                HStack {
                  Label(person.name, icon: .person)
                    .foregroundStyle(.primary)
                  Spacer()
                  if selectedPersonID == person.id {
                    Image(icon: .checkmark)
                      .foregroundStyle(.primary)
                  }
                }
              }
              .buttonStyle(.plain)
              .accessibilityLabel("\(person.name)を話者にする")
            }
          }
        }

        if !appliesToAllSegments {
          Section {
            Text("この発言の話者名だけを修正します。話者分離が曖昧な箇所は「？」で示します。")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }
      }
      .navigationTitle("話者を修正")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("保存", icon: .checkmark) {
            isSaving = true
            Task {
              let saved = await model.renameSpeaker(
                meetingID: meetingID, segmentID: segment.id, name: name,
                appliesToAllSegments: appliesToAllSegments)
              isSaving = false
              guard saved else { return }
              if let personID = selectedPersonID { addParticipant(personID) }
              dismiss()
            }
          }
          .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  /// Tags a chosen person on the recording unless they are already there.
  private func addParticipant(_ personID: UUID) {
    let alreadyTagged = model.participants(in: meetingID).contains { $0.id == personID }
    guard !alreadyTagged else { return }
    model.toggleParticipant(personID: personID, meeting: meetingID)
  }
}
