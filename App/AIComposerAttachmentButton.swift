import SwiftUI

/// Only the plus button morphs; the enclosing composer stays on screen.
struct AIComposerAttachmentButton: View {
  var offersMentions: Bool
  var onOpen: () -> Void
  var onSelect: (AIComposerAttachmentAction) -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isPresented = false
  @State private var pendingAction: AIComposerAttachmentAction?
  @Namespace private var presentationNamespace

  private var button: some View {
    ToolbarIconButton("添付を追加", icon: .plus) {
      onOpen()
      isPresented = true
    }
    .environment(\.memoraToolbarControlSize, MemoraIconMetrics.slot)
    .accessibilityHint("ファイルの添付やプラグイン・スキル・ソースの指定")
  }

  var body: some View {
    Group {
      if #available(iOS 26.0, *) {
        button.buttonStyle(.glass).buttonBorderShape(.circle)
      } else {
        button.buttonStyle(.plain).frame(width: 44, height: 44)
      }
    }
    .frame(width: 44, height: 44)
    .matchedTransitionSource(id: "attachments", in: presentationNamespace)
    .popover(isPresented: $isPresented) {
      menuContents
        .presentationCompactAdaptation(.popover)
        .navigationTransition(.zoom(sourceID: "attachments", in: presentationNamespace))
        .onDisappear {
          guard let action = pendingAction else { return }
          pendingAction = nil
          Task { @MainActor in
            // A picker or sheet must wait for the popover's dismissal.
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 180))
            onSelect(action)
          }
        }
    }
  }

  private var menuContents: some View {
    let actions = AIComposerAttachmentAction.allCases.filter { offersMentions || $0 != .mention }
    return VStack(spacing: 0) {
      ForEach(actions) { action in
        Button {
          pendingAction = action
          isPresented = false
        } label: {
          HStack(spacing: 14) {
            Image(icon: action.icon, size: 24)
              .frame(width: 44, height: 44)
              .background(MemoraPalette.textPrimary.opacity(0.045), in: Circle())
              .accessibilityHidden(true)
            Text(action.displayTitle)
              .font(.title3)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .foregroundStyle(MemoraPalette.textPrimary)
          .padding(.horizontal, MemoraSpacing.md)
          .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
          .contentShape(Rectangle())
        }
        .accessibilityLabel(action.title)
      }
    }
    .padding(MemoraSpacing.md)
    .frame(width: 292)
    .buttonStyle(MemoraMenuButtonStyle())
  }
}
