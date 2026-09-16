import SwiftUI

/// A drawer that slides the screen aside to reveal navigation beneath it.
///
/// The drawer keeps a single source of truth for how far it is open, so a drag,
/// a tap and a programmatic open can never disagree about where it sits. The
/// panel stays in the hierarchy at all times rather than being mounted and torn
/// down around the animation, which is what made the previous drawer drop
/// frames and occasionally strand itself half open.
struct SidebarContainer<Sidebar: View, Content: View>: View {
  @Binding var isOpen: Bool
  /// Screens that own the leading edge — a pushed detail, another tab — opt out
  /// so the drawer never competes with their own back gesture.
  var isEnabled: Bool
  @ViewBuilder var sidebar: () -> Sidebar
  @ViewBuilder var content: () -> Content

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var dragTranslation: CGFloat = 0
  /// Kept in step with the animation rather than a guessed timer, so the panel
  /// never disappears mid-slide and never lingers in the accessibility tree
  /// once it is closed.
  @State private var isPanelMounted = false
  /// Measured from the full-bleed container rather than a `GeometryReader`, so
  /// the content keeps filling the screen instead of being inset to the safe
  /// area, which left white bands above and below it.
  @State private var containerWidth: CGFloat = 0

  var body: some View {
    let width = min(320, containerWidth * 0.82)
    let offset = resolvedOffset(width: width)
    let progress = width > 0 ? offset / width : 0

    ZStack(alignment: .leading) {
      if isPanelMounted {
        sidebar()
          .frame(width: width)
          .frame(maxHeight: .infinity, alignment: .top)
          // Letting the panel trail slightly behind the content reads as
          // depth instead of two boards sliding as one.
          .offset(x: -(1 - progress) * width * 0.24)
          .opacity(progress)
          .allowsHitTesting(isOpen)
          .accessibilityHidden(!isOpen)
      }

      content()
        .clipShape(RoundedRectangle(cornerRadius: 28 * progress, style: .continuous))
        .overlay {
          if progress > 0 {
            // Kept transparent on purpose: the pushed-aside screen stays as
            // bright as it was, and only needs to catch a tap or drag to close.
            Color.clear
              .contentShape(Rectangle())
              .onTapGesture { setOpen(false) }
              .gesture(closeDrag(width: width))
              .allowsHitTesting(isOpen)
              .accessibilityLabel("メニューを閉じる")
              .accessibilityAddTraits(.isButton)
          }
        }
        .accessibilityHidden(isOpen)
        .offset(x: offset)
        .shadow(color: .black.opacity(0.2 * progress), radius: 24, x: -6)

      if isEnabled && !isOpen {
        // Narrow enough to stay out of the way of content taps, matching the
        // edge the system itself reserves for a back swipe.
        Color.clear
          .frame(width: 16)
          .frame(maxHeight: .infinity)
          .contentShape(Rectangle())
          .gesture(openDrag(width: width))
          .accessibilityHidden(true)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
    .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    .onChange(of: isEnabled) { _, enabled in
      guard !enabled, isOpen else { return }
      setOpen(false)
    }
  }

  private func resolvedOffset(width: CGFloat) -> CGFloat {
    min(max((isOpen ? width : 0) + dragTranslation, 0), width)
  }

  private func openDrag(width: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 12)
      .onChanged { value in
        guard !isOpen, isEnabled else { return }
        // A mostly vertical swipe belongs to the list underneath.
        guard abs(value.translation.width) > abs(value.translation.height) else { return }
        isPanelMounted = true
        dragTranslation = max(0, min(width, value.translation.width))
      }
      .onEnded { value in
        settle(value, width: width, wasOpen: false)
      }
  }

  private func closeDrag(width: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 12)
      .onChanged { value in
        guard isOpen else { return }
        dragTranslation = min(0, max(-width, value.translation.width))
      }
      .onEnded { value in
        settle(value, width: width, wasOpen: true)
      }
  }

  private func settle(_ value: DragGesture.Value, width: CGFloat, wasOpen: Bool) {
    let flick = value.predictedEndTranslation.width - value.translation.width
    let travelled = dragTranslation
    let shouldOpen = wasOpen
      ? !(travelled < -width / 3 || flick < -120)
      : (travelled > width / 3 || flick > 120)

    slide(to: shouldOpen)
  }

  private func setOpen(_ open: Bool) {
    slide(to: open)
  }

  private func slide(to open: Bool) {
    if open {
      isPanelMounted = true
    }

    withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
      dragTranslation = 0
      isOpen = open
    } completion: {
      guard !isOpen, dragTranslation == 0 else { return }
      isPanelMounted = false
    }
  }
}
