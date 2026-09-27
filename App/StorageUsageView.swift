import SwiftUI

/// Shows what Memora keeps on disk, and lets the audio be removed while the
/// transcript, summary, notes and tasks stay.
struct StorageUsageView: View {
  @Environment(MemoraModel.self) private var model
  @State private var breakdown = StorageUsage.Breakdown(audio: 0, photos: 0, other: 0)
  @State private var isBulkDeletePresented = false

  var body: some View {
    let audio = AudioUsage(meetings: model.meetings)

    List {
      Section("使用量") {
        usageRow("音声", breakdown.audio)
        usageRow("写真", breakdown.photos)
        usageRow("その他", breakdown.other)
        usageRow("合計", breakdown.total)
      }

      if !audio.largestFirst.isEmpty {
        Section {
          ForEach(audio.largestFirst, id: \.meeting.id) { item in
            let meeting = item.meeting
            HStack(alignment: .firstTextBaseline) {
              VStack(alignment: .leading, spacing: 2) {
                Text(meeting.displayTitle)
                  .lineLimit(1)
                Text(StorageUsage.text(item.bytes))
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
        Button("90日より前の音声を削除", icon: .trash) {
          isBulkDeletePresented = true
        }
        .disabled(audio.oldCount == 0)
      } footer: {
        if audio.oldCount == 0 {
          Text("90日より前の音声はありません。")
        } else {
          Text("\(audio.oldCount)件・\(StorageUsage.text(audio.oldBytes))を削除します。")
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
      Text("\(audio.oldCount)件・\(StorageUsage.text(audio.oldBytes))の音声を削除します。文字起こしと要約は残ります。取り消せます。")
    }
  }

  private func usageRow(_ title: String, _ bytes: Int64) -> some View {
    LabeledContent(title, value: StorageUsage.text(bytes))
      .accessibilityElement(children: .combine)
  }

  private func refresh() {
    breakdown = StorageUsage.current()
  }
}

/// Each record's audio with its size on disk, read once per redraw. Sorting by
/// size used to read the file sizes inside every comparison.
private struct AudioUsage {
  var largestFirst: [(meeting: Meeting, bytes: Int64)]
  var oldCount: Int
  var oldBytes: Int64

  init(meetings: [Meeting], now: Date = .now) {
    let cutoff = now.addingTimeInterval(-90 * 24 * 60 * 60)
    var sized: [(meeting: Meeting, bytes: Int64)] = []
    var oldCount = 0
    var oldBytes: Int64 = 0
    for meeting in meetings {
      guard let url = meeting.audioURL else { continue }
      let bytes = StorageUsage.size(of: url)
      sized.append((meeting, bytes))
      if meeting.createdAt < cutoff {
        oldCount += 1
        oldBytes += bytes
      }
    }
    largestFirst = sized.sorted { $0.bytes > $1.bytes }
    self.oldCount = oldCount
    self.oldBytes = oldBytes
  }
}
