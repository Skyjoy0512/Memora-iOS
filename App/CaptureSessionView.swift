import SwiftUI

struct CaptureSessionView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage("memora.haptics.enabled") private var hapticsEnabled = true
  @State private var section = CaptureSessionDetails.Section.notes
  @State private var isShowingDetails = false
  @State private var isDiscardConfirmationPresented = false
  @State private var selectedDetent = PresentationDetent.fraction(0.5)
  @State private var markerFeedback = 0

  var body: some View {
    VStack(spacing: MemoraSpacing.sm) {
      toolbar
      if isShowingDetails {
        RecordingElapsedLabel(compact: true)
        CaptureSessionDetails(section: $section)
          .frame(maxHeight: .infinity)
        detailsButton
      } else {
        overview
      }
      controls
    }
    .padding(.horizontal, MemoraSpacing.xl)
    .padding(.top, MemoraSpacing.md)
    .padding(.bottom, MemoraSpacing.sm)
    .presentationBackground(MemoraPalette.background)
    // The editors only open in the large detent, so the keyboard never
    // competes with a programmatic detent change while typing.
    .presentationDetents(
      dynamicTypeSize.isAccessibilitySize ? [.large] : [.fraction(0.5), .large],
      selection: $selectedDetent
    )
    .onChange(of: selectedDetent) { _, detent in
      if !dynamicTypeSize.isAccessibilitySize {
        isShowingDetails = detent == .large
      }
    }
    .onChange(of: dynamicTypeSize, initial: true) { _, size in
      selectedDetent = size.isAccessibilitySize || isShowingDetails ? .large : .fraction(0.5)
    }
    .onChange(of: canShowInputMeter, initial: true) { _, visible in
      model.setRecordingMeterVisible(visible)
    }
    .onDisappear { model.setRecordingMeterVisible(false) }
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

  private var canShowInputMeter: Bool {
    !isShowingDetails && !reduceMotion && scenePhase == .active
  }

  private var toolbar: some View {
    HStack(spacing: MemoraSpacing.sm) {
      Button {
        InteractionFeedback.shared.send(.tap)
        model.isCapturePresented = false
      } label: {
        Label("録音画面を閉じる", icon: .chevronDown)
          .labelStyle(.iconOnly)
          .frame(width: MemoraSpacing.touchTarget, height: MemoraSpacing.touchTarget)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityHint("録音は続きます")

      Spacer()

      markerButton
      Menu {
        Toggle("省電力", isOn: Binding(
          get: { model.recordingPowerMode == .lowPower },
          set: { model.recordingPowerMode = $0 ? .lowPower : .standard }
        ))
        Button("録音を破棄", icon: .trash, role: .destructive) {
          isDiscardConfirmationPresented = true
        }
        .disabled(model.isSavingCapture || !model.isRecording || model.hasUnsavedRecording)
      } label: {
        Label("録音のオプション", icon: .ellipsis)
          .labelStyle(.iconOnly)
          .frame(width: MemoraSpacing.touchTarget, height: MemoraSpacing.touchTarget)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("recording.options")
    }
  }

  private var markerButton: some View {
    Button {
      if model.addRecordingMarker() {
        markerFeedback += 1
        AccessibilityNotification.Announcement("重要マークを追加しました。\(model.recordingMarkers.count)件").post()
      }
    } label: {
      HStack(spacing: MemoraSpacing.xs) {
        Image(icon: .flag, size: 18)
        if !model.recordingMarkers.isEmpty {
          Text("\(model.recordingMarkers.count)").font(.caption.monospacedDigit())
        }
      }
      .frame(minWidth: MemoraSpacing.touchTarget, minHeight: MemoraSpacing.touchTarget)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!model.isRecording || model.isRecordingPaused || model.isSavingCapture)
    .accessibilityLabel("重要マークを追加")
    .accessibilityValue("\(model.recordingMarkers.count)件")
    .accessibilityHint(model.isRecordingPaused ? "録音を再開してから追加できます" : "今の録音位置を保存します")
    .sensoryFeedback(.success, trigger: markerFeedback) { _, _ in hapticsEnabled }
  }

  private var overview: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: MemoraSpacing.sm) {
          Spacer(minLength: MemoraSpacing.xs)
          RecordingElapsedLabel()
          if canShowInputMeter && model.isRecording && !model.isRecordingPaused
            && !model.recordingConservesResources && !model.isSavingCapture {
            RecordingInputMeter()
          }
          if model.recordingConservesResources {
            Text("省電力動作中")
              .font(.caption)
              .foregroundStyle(.secondary)
              .accessibilityHint("ライブ認識は休止します。録音品質は変わりません。")
          }
          if let spaceID = model.recordingSpaceID, let space = model.space(id: spaceID) {
            Label("保存先：\(space.name)", icon: .folder)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
          if let message = model.recordingStatusMessage {
            Label(message, icon: .exclamationmarkTriangle)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
          Spacer(minLength: MemoraSpacing.xs)
          detailsButton
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
      }
      .scrollBounceBehavior(.basedOnSize)
    }
  }

  private var detailsButton: some View {
    Button {
      withAnimation(reduceMotion ? nil : MemoraMotion.control) {
        isShowingDetails.toggle()
        if !dynamicTypeSize.isAccessibilitySize {
          selectedDetent = isShowingDetails ? .large : .fraction(0.5)
        }
      }
    } label: {
      Label(isShowingDetails ? "録音の概要に戻る" : "メモ・文字起こし",
        icon: isShowingDetails ? .chevronDown : .noteText)
        .font(.subheadline)
        .frame(minHeight: MemoraSpacing.touchTarget)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(.secondary)
    .accessibilityIdentifier("recording.details")
  }

  private var controls: some View {
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(spacing: MemoraSpacing.sm))
      : AnyLayout(HStackLayout(spacing: MemoraSpacing.sm))
    return layout {
      Button {
        model.toggleCapturePause()
        InteractionFeedback.shared.send(.selection)
      } label: {
        Label(model.isRecordingPaused ? "再開" : "一時停止",
          icon: model.isRecordingPaused ? .playFill : .pauseFill)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(MemoraButtonStyle(emphasis: .secondary))
      .disabled(model.isSavingCapture || !model.isRecording)

      Button {
        Task {
          guard model.isRecording, !model.isSavingCapture else { return }
          await model.stopCapture()
          InteractionFeedback.shared.send(model.hasUnsavedRecording ? .error : .success)
        }
      } label: {
        Text(model.isSavingCapture ? "保存しています…" : "終了して保存")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(MemoraButtonStyle())
      .disabled(model.isSavingCapture || !model.isRecording)
    }
  }
}
