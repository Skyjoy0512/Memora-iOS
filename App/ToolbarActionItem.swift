import SwiftUI

struct ToolbarActionItem<Content: View>: ToolbarContent {
  var usesSystemBackground = true
  var placement: ToolbarItemPlacement = .topBarTrailing
  @ViewBuilder var content: () -> Content

  var body: some ToolbarContent {
    if #available(iOS 26.0, *), !usesSystemBackground {
      ToolbarItem(placement: placement) {
        content()
          .buttonStyle(.plain)
          .environment(\.memoraToolbarControlSize, MemoraIconMetrics.touchTarget)
          .frame(width: MemoraIconMetrics.touchTarget, height: MemoraIconMetrics.touchTarget)
          .memoraGlass(in: Circle(), interactive: true, backed: false)
      }
      .sharedBackgroundVisibility(.hidden)
    } else {
      ToolbarItem(placement: placement) {
        content()
          // The system adds the surrounding padding for its native platter.
          .environment(\.memoraToolbarControlSize, MemoraIconMetrics.slot)
      }
    }
  }
}

extension EnvironmentValues {
  // Native toolbars supply the remaining padding; custom platters set 44pt.
  @Entry var memoraToolbarControlSize: CGFloat = MemoraIconMetrics.slot
}
