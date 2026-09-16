import SwiftUI
import UniformTypeIdentifiers

struct MemoraBottomBar: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var selection
  @Namespace private var captureGlass
  @State private var addFeedback = 0
  @State private var isFileImporterPresented = false

  var body: some View {
    @Bindable var model = model

    MemoraGlassContainer(spacing: 14) {
      HStack(spacing: 10) {
        HStack(spacing: 0) {
          BottomTabButton(tab: .files, title: "ファイル", symbol: "folder", selection: selection)
          BottomTabButton(tab: .lifeLog, title: "ライフログ", symbol: "waveform.path.ecg", selection: selection)
          BottomTabButton(tab: .search, title: "Ask AI", symbol: "sparkles", selection: selection)
          BottomTabButton(tab: .tasks, title: "タスク", symbol: "checklist", selection: selection)
          BottomTabButton(tab: .settings, title: "設定", symbol: "gearshape", selection: selection)
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .memoraGlass(in: Capsule())
        .compositingGroup()
        .blur(radius: model.isCaptureSourcePresented ? 8 : 0)
        .opacity(model.isCaptureSourcePresented ? 0.62 : 1)
        .overlay {
          if model.isCaptureSourcePresented {
            Capsule().fill(.regularMaterial)
          }
        }
        .allowsHitTesting(!model.isCaptureSourcePresented)
        .accessibilityHidden(model.isCaptureSourcePresented)

        captureButton
      }
      .overlay(alignment: .bottomTrailing) {
        if model.isCaptureSourcePresented {
          CaptureActionMenu(glassNamespace: captureGlass, onSelect: performCaptureAction)
            .padding(.bottom, 66)
            .transition(
              reduceMotion
                ? .opacity
                : .scale(scale: 0.72, anchor: .bottomTrailing).combined(with: .opacity)
            )
            .zIndex(1)
        }
      }
    }
    .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: model.selectedTab)
    .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: model.isCaptureSourcePresented)
    .sensoryFeedback(.selection, trigger: model.selectedTab)
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

private struct BottomTabButton: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var tab: RootTab
  var title: String
  var symbol: String
  var selection: Namespace.ID

  var body: some View {
    Button {
      guard model.selectedTab != tab else { return }
      withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
        model.selectedTab = tab
      }
    } label: {
      VStack(spacing: 2) {
        Image(systemName: symbol)
          .font(.body.weight(.medium))
          .symbolRenderingMode(.monochrome)

        Text(title)
          .font(.caption2.weight(isSelected ? .semibold : .medium))
          .lineLimit(1)
          .minimumScaleFactor(0.72)
      }
      .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
      .frame(maxWidth: .infinity, minHeight: 48)
      .background {
        if isSelected {
          BottomTabSelection(selection: selection)
        }
      }
      .blur(radius: model.isCaptureSourcePresented ? 8 : 0)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var isSelected: Bool {
    model.selectedTab == tab
  }
}

private struct BottomTabSelection: View {
  var selection: Namespace.ID

  var body: some View {
    if #available(iOS 26.0, *) {
      Color.clear
        .glassEffect(.regular.tint(Color.primary.opacity(0.12)), in: Capsule())
        .glassEffectID("selectedTab", in: selection)
        .glassEffectTransition(.matchedGeometry)
    } else {
      Capsule()
        .fill(Color.primary.opacity(0.1))
        .matchedGeometryEffect(id: "selectedTab", in: selection)
    }
  }
}
