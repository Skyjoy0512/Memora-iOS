import SwiftUI

struct CaptureSessionView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var section = CaptureSection.transcript
  @State private var stopFeedback = 0
  @State private var pauseFeedback = 0

  var body: some View {
    @Bindable var model = model

    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 12) {
        TextField("タイトルを追加", text: $model.recordingTitle, axis: .vertical)
          .font(.largeTitle.weight(.semibold))
          .lineLimit(1...2)
          .submitLabel(.done)

        Button("録音画面を閉じる", systemImage: "xmark") {
          model.isCapturePresented = false
        }
        .labelStyle(.iconOnly)
        .font(.body.weight(.semibold))
        .frame(width: 44, height: 44)
        .memoraGlass(in: Circle(), interactive: true)
      }
      .padding(.horizontal, 20)
      .padding(.top, 22)

      Picker("録音中の表示", selection: $section) {
        ForEach(CaptureSection.allCases) { item in
          Label(item.title, systemImage: item.symbol).tag(item)
        }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal, 20)
      .padding(.top, 18)

      Group {
        switch section {
        case .notes:
          TextEditor(text: $model.recordingNote)
            .font(.body)
            .scrollContentBackground(.hidden)
            .overlay(alignment: .topLeading) {
              if model.recordingNote.isEmpty {
                Text("メモを追加")
                  .foregroundStyle(.tertiary)
                  .padding(.horizontal, 5)
                  .padding(.vertical, 8)
                  .allowsHitTesting(false)
              }
            }
        case .transcript:
          VStack(spacing: 14) {
            Spacer()
            SiriWaveView(isPaused: model.isRecordingPaused)
              .frame(height: 84)
              .padding(.horizontal, 10)
            Text(model.isRecordingPaused ? "一時停止中" : "聞いています")
              .font(.subheadline.weight(.medium))
              .foregroundStyle(model.isRecordingPaused ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
            Text("文字起こしは録音を終了すると表示されます")
              .font(.footnote)
              .foregroundStyle(.secondary)
            Spacer()
          }
          .frame(maxWidth: .infinity)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(.horizontal, 20)
      .id(section)
      .transition(.opacity)
      .animation(reduceMotion ? nil : MemoraMotion.control, value: section)

      MemoraGlassContainer(spacing: 12) {
        HStack(spacing: 12) {
          Button(model.isRecordingPaused ? "再開" : "一時停止", systemImage: model.isRecordingPaused ? "play.fill" : "pause.fill") {
            pauseFeedback += 1
            model.toggleCapturePause()
          }
          .labelStyle(.titleOnly)
          .font(.headline)
          .frame(maxWidth: .infinity, minHeight: 56)
          .memoraGlass(in: Capsule(), interactive: true)

          HStack(spacing: 8) {
            Circle()
              .fill(model.isRecordingPaused ? Color.secondary : Color.red)
              .frame(width: 8, height: 8)
            Text(MemoraFormat.duration(model.recordingElapsed))
              .font(.subheadline.monospacedDigit().weight(.semibold))
              .contentTransition(.numericText())
          }
          .frame(minWidth: 86)
          .accessibilityElement(children: .combine)
          .accessibilityLabel("録音時間 \(MemoraFormat.duration(model.recordingElapsed))")

          Button("終了", systemImage: "stop.fill") {
            stopFeedback += 1
            Task { await model.stopCapture() }
          }
          .labelStyle(.titleOnly)
          .font(.headline)
          .foregroundStyle(Color(uiColor: .systemBackground))
          .frame(maxWidth: .infinity, minHeight: 56)
          .memoraGlass(in: Capsule(), tint: .primary, interactive: true)
        }
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 16)
    }
    .background(Color(uiColor: .systemBackground))
    .overlay { RecordingBottomBeam() }
    .presentationDetents([.fraction(0.7)])
    .presentationDragIndicator(.visible)
    .presentationCornerRadius(38)
    .interactiveDismissDisabled()
    .sensoryFeedback(.impact(weight: .medium), trigger: pauseFeedback)
    .sensoryFeedback(.impact(weight: .heavy), trigger: stopFeedback)
  }
}

private enum CaptureSection: String, CaseIterable, Identifiable {
  case notes
  case transcript

  var id: Self { self }

  var title: String {
    switch self {
    case .notes: "ノート"
    case .transcript: "文字起こし"
    }
  }

  var symbol: String {
    switch self {
    case .notes: "note.text"
    case .transcript: "waveform"
    }
  }
}
