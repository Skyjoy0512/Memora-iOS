import SwiftUI
import UniformTypeIdentifiers

/// The capture button and the palette that morphs out of it.
///
/// This sits above the frost that covers the rest of the screen while the menu
/// is open, which is what keeps it the one sharp, live thing on screen.
struct CaptureControl: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var captureGlass
  @State private var addFeedback = 0
  @State private var isFileImporterPresented = false

  var body: some View {
    MemoraGlassContainer(spacing: 14) {
      captureButton
        .overlay(alignment: .bottomTrailing) {
          if model.isCaptureSourcePresented {
            CaptureActionMenu(glassNamespace: captureGlass, onSelect: performCaptureAction)
              .padding(.bottom, 66)
              .transition(
                reduceMotion
                  ? .opacity
                  : .scale(scale: 0.72, anchor: .bottomTrailing).combined(with: .opacity)
              )
          }
        }
    }
    .fileImporter(
      isPresented: $isFileImporterPresented,
      allowedContentTypes: [.audio],
      allowsMultipleSelection: false,
      onCompletion: handleAudioImport
    )
    .onChange(of: model.selectedTab) { _, _ in
      collapseCaptureMenu()
    }
    .onDisappear {
      model.isCaptureSourcePresented = false
    }
  }

  @ViewBuilder
  private var captureButton: some View {
    let button = Button {
      addFeedback += 1
      withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) {
        model.isCaptureSourcePresented.toggle()
      }
    } label: {
      Image(systemName: "plus")
        .font(.title3.weight(.semibold))
        .rotationEffect(.degrees(model.isCaptureSourcePresented ? 45 : 0))
        .frame(width: 56, height: 56)
    }
    .buttonStyle(.plain)
    .foregroundStyle(.white)
    .sensoryFeedback(.impact(weight: .medium), trigger: addFeedback)
    .accessibilityLabel(model.isCaptureSourcePresented ? "作成メニューを閉じる" : "作成メニューを開く")
    .accessibilityHint(model.isCaptureSourcePresented ? "もう一度タップすると閉じます" : "録音やファイルの取り込み方法を選びます")

    if #available(iOS 26.0, *) {
      button
        .background(Circle().fill(.black))
        .glassEffect(.regular.tint(.black).interactive(), in: Circle())
        .glassEffectID("captureButton", in: captureGlass)
        .glassEffectTransition(.matchedGeometry)
    } else {
      button
        .background(.black, in: Circle())
        .overlay {
          Circle().stroke(.white.opacity(0.14), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
    }
  }

  private func performCaptureAction(_ action: CaptureAction) {
    collapseCaptureMenu()

    switch action {
    case .recording:
      Task {
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 180))
        await model.startCapture()
      }
    case .importAudio:
      isFileImporterPresented = true
    case .onlineMeeting:
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 180))
        model.isOnlineMeetingCapturePresented = true
      }
    case .project:
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 180))
        model.isFileCreationPresented = true
      }
    }
  }

  private func collapseCaptureMenu() {
    guard model.isCaptureSourcePresented else { return }
    withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
      model.isCaptureSourcePresented = false
    }
  }

  private func handleAudioImport(_ result: Result<[URL], any Error>) {
    switch result {
    case .success(let urls):
      guard let url = urls.first else { return }
      Task {
        await model.importAudio(from: url)
      }
    case .failure:
      model.importErrorMessage = "ファイルを選択できませんでした。もう一度お試しください。"
    }
  }
}
