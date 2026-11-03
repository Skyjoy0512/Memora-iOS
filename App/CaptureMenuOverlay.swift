import SwiftUI

/// A washed-out capture menu over the current screen. Its items fade in from
/// the top down so the eye reaches the primary action first.
struct CaptureMenuOverlay: View {
  var onSelect: (CaptureAction) -> Void
  var onClose: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let items: [CaptureAction] = [.recording, .importAudio, .onlineMeeting]

  var body: some View {
    ZStack {
      backdrop
      itemsList
      closeButton
    }
    .accessibilityAddTraits(.isModal)
  }

  private var backdrop: some View {
    ZStack {
      Rectangle().fill(.ultraThinMaterial)
      Color(uiColor: .systemBackground).opacity(0.72)
    }
    .ignoresSafeArea()
    .contentShape(Rectangle())
    .onTapGesture(perform: onClose)
    .accessibilityHidden(true)
  }

  private var itemsList: some View {
    VStack(alignment: .trailing, spacing: 26) {
      ForEach(Array(Self.items.enumerated()), id: \.element) { index, action in
        Button {
          InteractionFeedback.shared.send(.tap)
          onSelect(action)
        } label: {
          Text(title(for: action))
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(MemoraPalette.textPrimary)
            .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(action.detail)
        .memoraAppear(delay: Double(index) * 0.07)
      }
    }
    .padding(.trailing, 92)
    .offset(y: 48)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
  }

  private var closeButton: some View {
    Button(action: onClose) {
      Image(icon: .xmark, size: 26)
        .foregroundStyle(MemoraPalette.textPrimary)
        .frame(width: 52, height: 52)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("閉じる")
    .padding(.trailing, 20)
    .padding(.bottom, 12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
  }

  private func title(for action: CaptureAction) -> String {
    switch action {
    case .recording: "録音開始"
    case .importAudio: "音声インポート"
    case .onlineMeeting: "オンライン会議"
    default: action.title
    }
  }
}
