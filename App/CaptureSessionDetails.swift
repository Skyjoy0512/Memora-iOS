import SwiftUI

struct CaptureSessionDetails: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Binding var section: Section

  var body: some View {
    @Bindable var model = model
    return VStack(alignment: .leading, spacing: MemoraSpacing.md) {
      if let message = model.recordingInterruptionMessage {
        Label(message, icon: .exclamationmarkTriangle)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      MemoraSectionPicker(items: Section.allCases, selection: $section, title: \.title)

      Group {
        switch section {
        case .notes:
          VStack(alignment: .leading, spacing: MemoraSpacing.sm) {
            TextField("タイトルを追加", text: $model.recordingTitle, axis: .vertical)
              .font(.title3.weight(.semibold))
              .lineLimit(1...2)
              .submitLabel(.done)
              .accessibilityIdentifier("recording.title")

            if let event = model.captureEvent {
              Label("\(event.title)の予定から録音しています", icon: .calendar)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            TextEditor(text: $model.recordingNote)
              .font(.body)
              .accessibilityLabel("録音中のメモ")
              .scrollContentBackground(.hidden)
              .overlay(alignment: .topLeading) {
                if model.recordingNote.isEmpty {
                  Text("メモを追加")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, MemoraSpacing.sm)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
              }
          }
        case .transcript:
          RealtimeTranscriptView(service: model.realtimeTranscriber)
        case .markers:
          ScrollView {
            if model.recordingMarkers.isEmpty {
              ContentUnavailableView("重要マークはありません", icon: .flag,
                description: Text("旗のボタンで、あとから聞き返す位置を記録できます。"))
            } else {
              RecordingMarkersView(markers: model.recordingMarkers, onDelete: model.removeRecordingMarker)
            }
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .id(section)
      .transition(.opacity)
      .animation(reduceMotion ? nil : MemoraMotion.control, value: section)
    }
  }

  enum Section: CaseIterable {
    case notes
    case transcript
    case markers

    var title: String {
      switch self {
      case .notes: "ノート"
      case .transcript: "文字起こし"
      case .markers: "重要マーク"
      }
    }
  }
}
