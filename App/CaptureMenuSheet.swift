import SwiftUI

struct CaptureMenuSheet: View {
  var onSelect: (CaptureSheetAction) -> Void
  var onClose: () -> Void
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.verticalSizeClass) private var verticalSizeClass

  private static let shortcuts: [CaptureSheetAction] = [.camera, .photos, .files, .link]
  private static let items: [CaptureSheetAction] = [.recording, .importAudio, .onlineMeeting, .newNote]
  private let cornerRadius: CGFloat = 32

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          Spacer()
          Button(action: onClose) {
            Image(icon: .xmarkCircle, size: 24)
              .foregroundStyle(MemoraPalette.textSecondary)
              .frame(width: 44, height: 44)
              .contentShape(Circle())
          }
          .accessibilityLabel("閉じる")
        }
        .padding(.horizontal, 12)

        ScrollView(.horizontal) {
          MemoraGlassContainer(spacing: 12) {
            HStack(spacing: 12) {
              ForEach(Self.shortcuts) { action in
                Button { select(action) } label: {
                  VStack(spacing: 12) {
                    Image(icon: action.icon, size: 24).accessibilityHidden(true)
                    Text(action.title).font(.subheadline.weight(.medium))
                  }
                  .padding(.vertical, 16)
                  .frame(width: typeSize.isAccessibilitySize ? 160 : 104)
                  .frame(minHeight: 88)
                  .contentShape(RoundedRectangle(cornerRadius: 20))
                  .memoraGlass(in: RoundedRectangle(cornerRadius: 20), interactive: true, backed: false)
                }
                .accessibilityLabel(action.title)
              }
            }
          }
          .padding(.horizontal, 24)
          .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)

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
      .padding(.top, 8)
      .padding(.bottom, 20)
    }
    .scrollBounceBehavior(.basedOnSize)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .foregroundStyle(MemoraPalette.textPrimary)
    .buttonStyle(.plain)
    .presentationBackground(.regularMaterial)
    .presentationCornerRadius(cornerRadius)
    .presentationDetents(typeSize.isAccessibilitySize || verticalSizeClass == .compact
      ? [.large] : [.height(440), .large])
    .presentationDragIndicator(.visible)
    .presentationContentInteraction(.scrolls)
  }

  private func select(_ action: CaptureSheetAction) {
    InteractionFeedback.shared.send(.tap)
    onSelect(action)
  }
}
