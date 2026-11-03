import SwiftUI

struct CaptureMenuSheet: View {
  var onSelect: (CaptureAction) -> Void
  var onClose: () -> Void
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.verticalSizeClass) private var verticalSizeClass

  private static let items: [CaptureAction] = [.recording, .importAudio, .onlineMeeting]
  private let cornerRadius: CGFloat = 32

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("録音と取り込み")
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
          Spacer(minLength: 12)
          Button(action: onClose) {
            Image(icon: .xmark, size: 20)
              .frame(width: 44, height: 44)
              .contentShape(Circle())
          }
          .accessibilityLabel("閉じる")
        }

        ForEach(Self.items) { action in
          Button {
            InteractionFeedback.shared.send(.tap)
            onSelect(action)
          } label: {
            HStack(spacing: 14) {
              Image(icon: action.symbol, size: 22)
                .frame(width: 28)
                .accessibilityHidden(true)
              Text(title(for: action))
                .font(.title3.weight(.medium))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
          }
          .accessibilityHint(action.detail)
        }
      }
      .padding(.horizontal, 24)
      .padding(.top, 20)
      .padding(.bottom, 20)
    }
    .scrollBounceBehavior(.basedOnSize)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .foregroundStyle(MemoraPalette.textPrimary)
    .buttonStyle(.plain)
    .background {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(.clear)
        .memoraGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), backed: false)
        .ignoresSafeArea()
    }
    .presentationBackground(.clear)
    .presentationCornerRadius(cornerRadius)
    .presentationDetents(typeSize.isAccessibilitySize || verticalSizeClass == .compact
      ? [.large] : [.height(300), .large])
    .presentationDragIndicator(.visible)
    .presentationContentInteraction(.scrolls)
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
