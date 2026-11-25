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
  @State private var dragTranslation: CGFloat = 0

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
          // Keep the mounted panel outside the viewport while closed so
          // hosting views cannot expose controls at their old positions.
          .offset(x: -(1 - progress) * width)
          .opacity(progress)
          .allowsHitTesting(isOpen)
          .accessibilityElement(children: .contain)
          .accessibilityAddTraits(.isModal)
          .accessibilityAction(.escape) { setOpen(false) }
          .accessibilityHidden(!isOpen)

        content()
          .frame(width: proxy.size.width, height: proxy.size.height)
          .compositingGroup()
          .overlay(alignment: .top) {
            // Keep scrolling text out of the status-bar strip, including the
            // part of the presenting screen visible above a sheet.
            MemoraPalette.background
              .frame(height: proxy.safeAreaInsets.top)
              .offset(y: -proxy.safeAreaInsets.top)
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }
          .accessibilityHidden(isOpen)
          .overlay {
            if isOpen || progress > 0 {
              // A light wash, not a blur: the pushed-aside screen stays readable
              // behind the drawer. It also catches the tap or drag that closes it.
              Button { setOpen(false) } label: {
                Rectangle()
                  .fill(Color(uiColor: .systemBackground).opacity(0.45))
                  .frame(width: max(0, proxy.size.width - offset))
                  .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .accessibilityLabel("メニューを閉じる")
              .accessibilityHidden(!isOpen)
              .gesture(closeDrag(width: width))
              .allowsHitTesting(isOpen)
              .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          // Clip the closing overlay too, so it cannot fill the rounded corners.
          .mask {
            RoundedRectangle(cornerRadius: 56 * progress, style: .continuous)
              .ignoresSafeArea(.container)
          }
          .modifier(SidebarSlideEffect(offset: offset, onClosed: onCloseAnimationCompleted))
          .shadow(color: .black.opacity(0.08 * progress), radius: 8, x: -4)

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
    .background {
      (isOpen ? MemoraPalette.secondaryBackground : MemoraPalette.background)
        .ignoresSafeArea(.container)
    }
    .onChange(of: isEnabled) { _, enabled in
      guard !enabled, isOpen else { return }
      setOpen(false)
    }
    .onChange(of: isOpen) { _, open in
      if !open && reduceMotion { onCloseAnimationCompleted() }
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

extension EnvironmentValues {
  @Entry var revealMemoraSidebar: MemoraSidebarAction? = nil
}
