import SwiftUI

struct CaptureMenuSheet: View {
  var onSelect: (CaptureSheetAction) -> Void
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.verticalSizeClass) private var verticalSizeClass

  private static let items: [CaptureSheetAction] = FeatureFlags.isOnlineMeetingCaptureEnabled
    ? [.recording, .importAudio, .onlineMeeting, .newNote] : [.recording, .importAudio, .newNote]
  private let cornerRadius: CGFloat = 32

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        VStack(spacing: 2) {
          ForEach(Self.items) { action in
            if action == .newNote { Divider().padding(.vertical, 8) }
            Button { select(action) } label: {
              HStack(spacing: 16) {
                Image(icon: action.icon, size: 22)
                  .frame(width: 28).accessibilityHidden(true)
                Text(action.title)
                  .font(.body.weight(.medium))
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .multilineTextAlignment(.leading)
              }
              .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
              .contentShape(Rectangle())
            }
          }
        }
        .padding(.horizontal, 24)
      }
      .padding(.top, 24)
      .padding(.bottom, 20)
    }
    .scrollBounceBehavior(.basedOnSize)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .foregroundStyle(MemoraPalette.textPrimary)
    .buttonStyle(.plain)
    .presentationBackground(.regularMaterial)
    .presentationCornerRadius(cornerRadius)
    .presentationDetents(typeSize.isAccessibilitySize || verticalSizeClass == .compact
      ? [.large] : [.height(84 + CGFloat(Self.items.count) * 56), .large])
    .presentationDragIndicator(.visible)
    .presentationContentInteraction(.scrolls)
  }

  private func select(_ action: CaptureSheetAction) {
    InteractionFeedback.shared.send(.tap)
    onSelect(action)
  }
}
