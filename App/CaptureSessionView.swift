import SwiftUI

struct CaptureSessionView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var section = CaptureSection.notes
  @State private var stopFeedback = 0
  @State private var pauseFeedback = 0
  @State private var isDiscardConfirmationPresented = false

  var body: some View {
    @Bindable var model = model

    VStack(spacing: 0) {
      HStack(spacing: 12) {
        HStack(spacing: 8) {
          Circle()
            .fill(model.isRecordingPaused ? Color.secondary : Color.red)
            .frame(width: 8, height: 8)

          Text(MemoraFormat.duration(model.recordingElapsed))
            .font(.subheadline.monospacedDigit().weight(.semibold))
            .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("録音時間 \(MemoraFormat.duration(model.recordingElapsed))")

        Spacer()

        Button("録音を破棄", systemImage: "trash") {
          isDiscardConfirmationPresented = true
        }
        .labelStyle(.iconOnly)
        .font(.body.weight(.semibold))
        .foregroundStyle(.red)
        .frame(width: 44, height: 44)
        .memoraGlass(in: Circle(), interactive: true)

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

      TextField("タイトルを追加", text: $model.recordingTitle, axis: .vertical)
        .font(.title2.weight(.semibold))
        .lineLimit(1...2)
        .submitLabel(.done)
        .padding(.horizontal, 20)
        .padding(.top, 16)

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
          Color.clear
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
    .presentationBackground {
      sheetBackground
    }
    .presentationDetents([.fraction(0.5)])
    .presentationDragIndicator(.visible)
    .presentationCornerRadius(38)
    .interactiveDismissDisabled()
    .confirmationDialog(
      "録音を破棄しますか？",
      isPresented: $isDiscardConfirmationPresented,
      titleVisibility: .visible
    ) {
      Button("破棄", role: .destructive) {
        Task { await model.cancelCapture() }
      }
      Button("キャンセル", role: .cancel) {}
    } message: {
      Text("録音した音声は保存されず、文字起こしも作成しません。")
    }
    .sensoryFeedback(.impact(weight: .medium), trigger: pauseFeedback)
    .sensoryFeedback(.impact(weight: .heavy), trigger: stopFeedback)
  }

  /// A Liquid Glass surface with the live voice glow gathering at the bottom.
  private var sheetBackground: some View {
    ZStack(alignment: .bottom) {
      Rectangle()
        .fill(.regularMaterial)

      VoiceGlow(
        level: model.recordingLevel,
        isActive: model.isRecording && !model.isRecordingPaused
      )
      .frame(height: 300)
    }
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
