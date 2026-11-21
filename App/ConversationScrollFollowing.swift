import SwiftUI

struct ConversationScrollFollowing: ViewModifier {
  static let bottomID = "memora-conversation-bottom"
  var proxy: ScrollViewProxy
  var latestMessageID: UUID?
  var isBusy = false
  var bottomInset: CGFloat = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var position = ConversationScrollState()
  @State private var isUserDriven = false

  func body(content: Content) -> some View {
    content
      .onScrollPhaseChange { _, phase in
        isUserDriven = phase == .tracking || phase == .interacting || phase == .decelerating
      }
      .onScrollGeometryChange(for: ConversationScrollState.Viewport.self) { geometry in
        .init(offset: geometry.contentOffset.y, height: geometry.containerSize.height,
          contentHeight: geometry.contentSize.height, bottomInset: geometry.contentInsets.bottom)
      } action: { _, viewport in
        if position.update(viewport, isUserDriven: isUserDriven, isStreaming: isBusy) { scroll(animated: false) }
      }
      .onChange(of: latestMessageID) { _, _ in
        if position.contentArrived() { scroll(animated: true) }
      }
      .onChange(of: isBusy) { _, busy in
        if !busy && position.followsLatest && !isUserDriven { scroll(animated: false) }
      }
      .onAppear { if position.followsLatest { scroll(animated: false) } }
      .overlay(alignment: .bottom) {
        if position.hasUnseenContent {
          Button {
            position.follow()
            scroll(animated: true)
          } label: {
            Label("新しい回答", icon: .arrowDown)
              .font(.subheadline.weight(.semibold))
              .padding(.horizontal, MemoraSpacing.lg)
              .frame(minHeight: MemoraSpacing.touchTarget)
              .background(.thinMaterial, in: Capsule())
              .contentShape(Capsule())
          }
          .padding(.bottom, bottomInset)
          .accessibilityLabel("新しい回答を表示")
        }
      }
  }

  private func scroll(animated: Bool) {
    withAnimation(animated && !reduceMotion ? .smooth(duration: 0.3) : nil) {
      proxy.scrollTo(Self.bottomID, anchor: .bottom)
    }
  }
}
