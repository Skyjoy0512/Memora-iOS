import SwiftUI

enum CaptureAction: CaseIterable, Identifiable {
  case recording
  case importAudio
  case onlineMeeting
  case project

  var id: Self { self }

  var title: String {
    switch self {
    case .recording: "録音を開始"
    case .importAudio: "音声を取り込む"
    case .onlineMeeting: "オンライン会議"
    case .project: "プロジェクトを作成"
    }
  }

  var symbol: String {
    switch self {
    case .recording: "waveform"
    case .importAudio: "square.and.arrow.down"
    case .onlineMeeting: "video"
    case .project: "folder.badge.plus"
    }
  }
}

/// An inline action palette that morphs out of the persistent capture FAB.
struct CaptureActionMenu: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var glassNamespace: Namespace.ID
  var onSelect: (CaptureAction) -> Void
  @State private var visibleItemCount = 0

  var body: some View {
    menuSurface
      .task {
        await revealItems()
      }
  }

  @ViewBuilder
  private var menuSurface: some View {
    let content = menuContent
      .padding(10)
      .frame(width: 292)

    if #available(iOS 26.0, *) {
      content
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .glassEffectID("captureMenu", in: glassNamespace)
        .glassEffectTransition(.matchedGeometry)
        .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
    } else {
      content
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 28, style: .continuous)
            .stroke(Color(uiColor: .separator).opacity(0.55), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.14), radius: 24, y: 10)
    }
  }

  private var menuContent: some View {
    VStack(spacing: 2) {
      ForEach(Array(CaptureAction.allCases.enumerated()), id: \.element.id) { index, action in
        CaptureSourceButton(symbol: action.symbol, title: action.title) {
          onSelect(action)
        }
        .opacity(index < visibleItemCount ? 1 : 0)
        .offset(y: index < visibleItemCount ? 0 : 8)
        .allowsHitTesting(index < visibleItemCount)
        .accessibilityHidden(index >= visibleItemCount)
      }
    }
  }

  private func revealItems() async {
    if reduceMotion {
      visibleItemCount = CaptureAction.allCases.count
      return
    }

    for count in 1...CaptureAction.allCases.count {
      try? await Task.sleep(for: .milliseconds(45))
      guard !Task.isCancelled else { return }
      withAnimation(.snappy(duration: 0.24)) {
        visibleItemCount = count
      }
    }
  }
}

private struct CaptureSourceButton: View {
  var symbol: String
  var title: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 14) {
        Image(systemName: symbol)
          .font(.title3.weight(.semibold))
          .symbolRenderingMode(.monochrome)
          .frame(width: 42, height: 42)
          .background(Color.primary.opacity(0.07), in: Circle())

        Text(title)
          .font(.body.weight(.semibold))
          .foregroundStyle(.primary)

        Spacer(minLength: 12)
      }
      .padding(.horizontal, 8)
      .frame(maxWidth: .infinity, minHeight: 54)
      .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

struct OnlineMeetingCaptureView: View {
  var beginRecording: () -> Void

  var body: some View {
    List {
      Section {
        Label("Zoom", systemImage: "video")
        Label("Google Meet", systemImage: "video")
        Label("Microsoft Teams", systemImage: "video")
      } header: {
        Text("対応する会議")
      } footer: {
        Text("会議をスピーカーで再生し、Memoraをバックグラウンドで録音します。開始前に参加者へ録音を知らせてください。")
      }

      Section {
        Button("録音の準備をする", systemImage: "waveform", action: beginRecording)
      }
    }
    .navigationTitle("オンライン会議")
    .navigationBarTitleDisplayMode(.inline)
  }
}
