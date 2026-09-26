import SwiftUI

/// Shows what Memora keeps on disk, and lets the audio be removed while the
/// transcript, summary, notes and tasks stay.
struct StorageUsageView: View {
  @Environment(MemoraModel.self) private var model
  @State private var breakdown = StorageUsage.Breakdown(audio: 0, photos: 0, other: 0)
  @State private var isBulkDeletePresented = false

  var body: some View {
    List {
      Section("使用量") {
        usageRow("音声", breakdown.audio)
        usageRow("写真", breakdown.photos)
        usageRow("その他", breakdown.other)
        usageRow("合計", breakdown.total)
      }

      if !audioMeetings.isEmpty {
        Section {
          ForEach(audioMeetings) { meeting in
            HStack(alignment: .firstTextBaseline) {
              VStack(alignment: .leading, spacing: 2) {
                Text(meeting.displayTitle)
                  .lineLimit(1)
                Text(StorageUsage.text(StorageUsage.size(of: audioURL(meeting))))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer(minLength: 8)
              Button("音声を削除") {
                model.removeMeetingAudio(meeting.id)
                refresh()
              }
              .font(.subheadline.weight(.medium))
            }
          }
        } header: {
          Text("記録ごとの音声")
        } footer: {
          Text("音声だけを削除します。文字起こし・要約・ノート・タスクは残ります。")
        }
      }

      Section {
        Button("90日より前の音声を削除", systemImage: "trash") {
          isBulkDeletePresented = true
        }
        .disabled(oldAudioMeetings.isEmpty)
      } footer: {
        if oldAudioMeetings.isEmpty {
          Text("90日より前の音声はありません。")
        } else {
          Text("\(oldAudioMeetings.count)件・\(StorageUsage.text(oldAudioTotal))を削除します。")
        }
      }
    }
    .navigationTitle("保存容量")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { refresh() }
    .confirmationDialog(
      "90日より前の音声を削除しますか？",
      isPresented: $isBulkDeletePresented,
      titleVisibility: .visible
    ) {
      Button("削除", role: .destructive) {
        model.removeAudio(olderThanDays: 90)
        refresh()
      }
      Button("キャンセル", role: .cancel) {}
    } message: {
      Text("\(oldAudioMeetings.count)件・\(StorageUsage.text(oldAudioTotal))の音声を削除します。文字起こしと要約は残ります。取り消せます。")
    }
  }

  private func usageRow(_ title: String, _ bytes: Int64) -> some View {
    LabeledContent(title, value: StorageUsage.text(bytes))
      .accessibilityElement(children: .combine)
  }

  private func refresh() {
    breakdown = StorageUsage.current()
  }

  private func audioURL(_ meeting: Meeting) -> URL {
    meeting.audioURL ?? URL(fileURLWithPath: "/dev/null")
  }

  private var audioMeetings: [Meeting] {
    model.meetings
      .filter { $0.audioURL != nil }
      .sorted { StorageUsage.size(of: audioURL($0)) > StorageUsage.size(of: audioURL($1)) }
  }

  private var oldAudioMeetings: [Meeting] {
    let cutoff = Date.now.addingTimeInterval(-90 * 24 * 60 * 60)
    return model.meetings.filter { $0.audioURL != nil && $0.createdAt < cutoff }
  }

  private var oldAudioTotal: Int64 {
    oldAudioMeetings.reduce(0) { $0 + StorageUsage.size(of: audioURL($1)) }
  }
}
