import SwiftUI

private struct BottomBarScrollBehavior: ViewModifier {
  @Environment(MemoraModel.self) private var model
  /// Which screen this scroll view belongs to, so it can only speak for itself.
  var screenID: String
  /// Whether a finger or its momentum is moving the list. Only that may move
  /// the bar: showing or hiding the bar changes the list's insets, and the
  /// offset change that causes must not be read as more scrolling, or the bar
  /// and the list push each other back and forth and the list stops scrolling.
  /// Rows being measured as they appear move the offset too, which once hid
  /// the bar again right after scrolling up had brought it back.
  @State private var isUserScrolling = false
  /// When the bar last moved; the layout settling after it is ignored.
  @State private var lastChange = Date.distantPast

  func body(content: Content) -> some View {
    content
      .onScrollPhaseChange { _, phase in
        isUserScrolling = switch phase {
        case .tracking, .interacting, .decelerating: true
        default: false
        }
      }
      .onScrollGeometryChange(for: ScrollPosition.self) { geometry in
        let offset = geometry.contentOffset.y + geometry.contentInsets.top
        let maxOffset = geometry.contentSize.height + geometry.contentInsets.top
          + geometry.contentInsets.bottom - geometry.containerSize.height
        return ScrollPosition(offset: offset, maxOffset: maxOffset)
      } action: { previous, position in
        update(from: previous, to: position)
      }
      .onAppear {
        // Hidden controls are hard to find with VoiceOver, so they stay put.
        if UIAccessibility.isVoiceOverRunning {
          setHidden(false)
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
        if UIAccessibility.isVoiceOverRunning {
          setHidden(false)
        }
      }
      .onDisappear {
        setHidden(false)
      }
  }

  private func update(from previous: ScrollPosition, to position: ScrollPosition) {
    // Back at the top always brings the bar home.
    if position.offset <= 24 {
      setHidden(false)
      return
    }
    guard isUserScrolling, Date.now.timeIntervalSince(lastChange) > Self.settleTime else { return }
    // A list measures rows as they come into view and corrects its size, which
    // moves the offset by the same amount without anyone scrolling. Only a move
    // with the content size unchanged says which way the person is going.
    guard abs(position.maxOffset - previous.maxOffset) < 0.5 else { return }
    // At the end of the list, the bar's own inset change moves the offset, so
    // the bar keeps whatever state it has until the list is scrolled back up.
    guard position.offset < position.maxOffset - Self.endZone else { return }

    if position.offset > previous.offset + 4 {
      setHidden(true)
    } else if position.offset < previous.offset - 4 {
      setHidden(false)
    }
  }

  private static let settleTime: TimeInterval = 0.4
  private static let endZone: CGFloat = 160

  private func setHidden(_ hidden: Bool) {
    guard !UIAccessibility.isVoiceOverRunning else {
      model.setBottomBarHidden(false, for: screenID)
      return
    }
    guard model.isBottomBarHidden(for: screenID) != hidden else { return }
    lastChange = .now
    model.setBottomBarHidden(hidden, for: screenID)
  }
}

/// Where a scroll view is, and how far it can go, read together.
private struct ScrollPosition: Equatable {
  var offset: CGFloat
  var maxOffset: CGFloat
}

extension View {
  /// `screenID` names the screen so only the screen being read can hide the bar.
  func hideBottomBarOnScroll(_ screenID: String) -> some View {
    modifier(BottomBarScrollBehavior(screenID: screenID))
  }
}
