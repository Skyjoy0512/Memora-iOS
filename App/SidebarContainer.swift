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
  var onCloseAnimationCompleted: () -> Void = {}
  @ViewBuilder var sidebar: () -> Sidebar
  @ViewBuilder var content: () -> Content

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var dragTranslation: CGFloat = 0
  /// The drawer breaks out of the safe area so the app can fill the screen, so
  /// the panel reads the window's insets directly to keep its own contents clear
  /// of the status bar and home indicator.
  @State private var windowInsets = EdgeInsets()

  var body: some View {
    GeometryReader { proxy in
      let width = min(320, proxy.size.width * 0.82)
      let offset = resolvedOffset(width: width)
      let progress = width > 0 ? offset / width : 0

      ZStack(alignment: .leading) {
        // Always in the hierarchy so a programmatic open and a drag animate the
        // same way; `progress` alone decides whether it is seen or interactive.
        sidebar()
          .frame(width: width)
          .frame(maxHeight: .infinity, alignment: .top)
          // The panel's own background bleeds to the edges; its contents stay
          // clear of the status bar and home indicator.
          .padding(.top, windowInsets.top)
          .padding(.bottom, windowInsets.bottom)
          // Letting the panel trail slightly behind the content reads as
          // depth instead of two boards sliding as one.
          .offset(x: -(1 - progress) * width * 0.24)
          .opacity(progress)
          .allowsHitTesting(isOpen)
          .accessibilityHidden(!isOpen)

        content()
          .frame(width: proxy.size.width, height: proxy.size.height)
          .compositingGroup()
          .clipShape(RoundedRectangle(cornerRadius: 28 * progress, style: .continuous))
          .overlay {
            if isOpen || progress > 0 {
              // A light wash, not a blur: the pushed-aside screen stays readable
              // behind the drawer. It also catches the tap or drag that closes it.
              Rectangle()
                .fill(Color(uiColor: .systemBackground).opacity(0.45))
                .contentShape(Rectangle())
                .onTapGesture { setOpen(false) }
                .gesture(closeDrag(width: width))
                .allowsHitTesting(isOpen)
                .accessibilityLabel("メニューを閉じる")
                .accessibilityAddTraits(.isButton)
            }
          }
          .accessibilityHidden(isOpen)
          .modifier(SidebarSlideEffect(offset: offset, onClosed: onCloseAnimationCompleted))
          .shadow(color: .black.opacity(0.10 * progress), radius: 12, x: -3)

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
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    // Fill the screen but keep the keyboard's safe area, so the composer rises
    // above the keyboard instead of staying hidden behind it.
    .ignoresSafeArea(.container, edges: .all)
    .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    .onChange(of: isEnabled) { _, enabled in
      guard !enabled, isOpen else { return }
      setOpen(false)
    }
    .onChange(of: isOpen) { _, open in
      if !open && reduceMotion { onCloseAnimationCompleted() }
    }
    .onGeometryChange(for: CGSize.self) { $0.size } action: { _ in refreshWindowInsets() }
    .onChange(of: scenePhase) { _, _ in refreshWindowInsets() }
    .onAppear { refreshWindowInsets() }
    .task {
      // The window may not be key yet on the first pass, so re-read once the
      // first layout has settled.
      refreshWindowInsets()
    }
  }

  private func refreshWindowInsets() {
    let insets = WindowSafeArea.insets
    if insets != windowInsets {
      windowInsets = insets
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
    withAnimation(reduceMotion ? nil : MemoraMotion.drawer) {
      dragTranslation = 0
      isOpen = open
    }
  }
}
