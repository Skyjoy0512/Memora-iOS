import SwiftUI

struct CaptureSessionView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var section = CaptureSection.notes
  @State private var isDiscardConfirmationPresented = false
  @State private var selectedDetent = PresentationDetent.fraction(0.5)

  var body: some View {
    @Bindable var model = model

    VStack(spacing: 0) {
      HStack(spacing: 12) {
        RecordingElapsedLabel()

        Spacer()

        Button {
          if model.addRecordingMarker() {
            section = .markers
          }
        } label: {
          Image(icon: .flag)
            .font(.body.weight(.semibold))
            .frame(width: 44, height: 44)
            .memoraGlass(in: Circle(), interactive: true)
        }
        .disabled(!model.isRecording || model.isRecordingPaused || model.isSavingCapture)
        .accessibilityLabel("重要マークを追加")
        .accessibilityValue("\(model.recordingMarkers.count)件")
        .accessibilityHint(model.isRecordingPaused ? "録音を再開してから追加できます" : "今の録音位置を保存します")

        Button("録音を破棄", icon: .trash) {
          isDiscardConfirmationPresented = true
        }
        .labelStyle(.iconOnly)
        .font(.body.weight(.semibold))
        .foregroundStyle(.red)
        .frame(width: 44, height: 44)
        .memoraGlass(in: Circle(), interactive: true)

        Button("録音画面を閉じる", icon: .xmark) {
          InteractionFeedback.shared.send(.tap)
          model.isCapturePresented = false
        }
        .labelStyle(.iconOnly)
        .font(.body.weight(.semibold))
        .frame(width: 44, height: 44)
        .memoraGlass(in: Circle(), interactive: true)
      }
      .padding(.horizontal, MemoraSpacing.xl)
      .padding(.top, MemoraSpacing.xxl)

      if let spaceID = model.recordingSpaceID, let space = model.space(id: spaceID) {
        Label("保存先：\(space.name)", icon: .folder)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, MemoraSpacing.xl)
          .padding(.top, MemoraSpacing.sm)
      }

      if let message = model.recordingInterruptionMessage {
        Label(message, icon: .exclamationmarkTriangle)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, MemoraSpacing.xl)
          .padding(.top, MemoraSpacing.md)
          .accessibilityLabel(message)
      }

      MemoraSectionPicker(items: CaptureSection.allCases, selection: $section, title: \.title)
      .padding(.horizontal, MemoraSpacing.xl)
      .padding(.top, MemoraSpacing.lg)

      TextField("タイトルを追加", text: $model.recordingTitle, axis: .vertical)
        .font(.title2.weight(.semibold))
        .lineLimit(1...2)
        .submitLabel(.done)
        .padding(.horizontal, MemoraSpacing.xl)
        .padding(.top, MemoraSpacing.lg)

      if let event = model.captureEvent {
        Label("\(event.title)の予定から録音しています", icon: .calendar)
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, MemoraSpacing.xl)
          .padding(.top, MemoraSpacing.sm)
          .accessibilityLabel("予定\(event.title)から録音しています。タイトルは変更できます")
      }

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
                  .padding(.vertical, MemoraSpacing.sm)
                  .allowsHitTesting(false)
              }
            }
        case .transcript:
          RealtimeTranscriptView(service: model.realtimeTranscriber)
        case .markers:
          ScrollView {
            if model.recordingMarkers.isEmpty {
              ContentUnavailableView("重要マークはありません", icon: .flag,
                description: Text("大事だと思った瞬間に上の旗をタップすると、録音の位置を残せます。"))
            } else {
              RecordingMarkersView(markers: model.recordingMarkers, onDelete: model.removeRecordingMarker)
            }
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(.horizontal, MemoraSpacing.xl)
      .id(section)
      .transition(.opacity)
      .animation(reduceMotion ? nil : MemoraMotion.control, value: section)

      MemoraGlassContainer(spacing: 12) {
        HStack(spacing: 12) {
          Button(model.isRecordingPaused ? "再開" : "一時停止", icon: model.isRecordingPaused ? .playFill : .pauseFill) {
            model.toggleCapturePause()
            InteractionFeedback.shared.send(.selection)
          }
          .labelStyle(.titleOnly)
          .font(.headline)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
          .frame(maxWidth: .infinity, minHeight: 56)
          .memoraGlass(in: Capsule(), interactive: true)

          Button(model.isSavingCapture ? "保存しています…" : "終了して保存", icon: .stopFill) {
            Task {
              guard model.isRecording, !model.isSavingCapture else { return }
              await model.stopCapture()
              InteractionFeedback.shared.send(model.hasUnsavedRecording ? .error : .success)
            }
          }
          .disabled(model.isSavingCapture)
          .labelStyle(.titleOnly)
          .font(.headline)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity, minHeight: 56)
          .memoraGlass(in: Capsule(), tint: .accentColor, interactive: true)
        }
      }
      .padding(.horizontal, MemoraSpacing.lg)
      .padding(.bottom, MemoraSpacing.lg)
    }
    .presentationBackground {
      sheetBackground
    }
    // Extra-large text needs more room than the half sheet gives, and the
    // keyboard needs the tall sheet so the field it is editing stays visible.
    .presentationDetents(
      dynamicTypeSize.isAccessibilitySize ? [.large] : [.fraction(0.5), .large],
      selection: $selectedDetent
    )
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
      withAnimation(reduceMotion ? nil : MemoraMotion.control) {
        selectedDetent = .large
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
      guard !dynamicTypeSize.isAccessibilitySize else { return }
      withAnimation(reduceMotion ? nil : MemoraMotion.control) {
        selectedDetent = .fraction(0.5)
      }
    }
    .onAppear {
      if dynamicTypeSize.isAccessibilitySize {
        selectedDetent = .large
      }
      // The glow is the only reader of the level, so sampling runs only while
      // this sheet is on screen. Recording itself is unaffected.
      model.levelMeter.isActive = true
    }
    .onDisappear {
      model.levelMeter.isActive = false
    }
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
  }

  /// A Liquid Glass surface with the live voice glow gathering at the bottom.
  private var sheetBackground: some View {
    ZStack(alignment: .bottom) {
      Rectangle()
        .fill(.regularMaterial)

      VoiceGlow(
        level: model.levelMeter.level,
        isActive: model.isRecording && !model.isRecordingPaused
      )
      .frame(height: 300)
    }
  }
}

private enum CaptureSection: String, CaseIterable, Identifiable {
  case notes
  case transcript
  case markers

  var id: Self { self }

  var title: String {
    switch self {
    case .notes: "ノート"
    case .transcript: "文字起こし"
    case .markers: "重要マーク"
    }
  }

  var symbol: MemoraIcon {
    switch self {
    case .notes: .noteText
    case .transcript: .waveform
    case .markers: .flag
    }
  }
}
