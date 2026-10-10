import SwiftUI

struct ToolbarActionItem<Content: View>: ToolbarContent {
  var usesSystemBackground = false
  @ViewBuilder var content: () -> Content

  var body: some ToolbarContent {
    if #available(iOS 26.0, *), !usesSystemBackground {
      ToolbarItem(placement: .topBarTrailing) {
        content()
          .buttonStyle(.plain)
          .environment(\.memoraToolbarControlSize, 44)
          .frame(width: 44, height: 44)
          .memoraGlass(in: Circle(), interactive: true, backed: false)
      }
      .sharedBackgroundVisibility(.hidden)
    } else {
      ToolbarItem(placement: .topBarTrailing) {
        content()
      }
    }
  }
}

extension EnvironmentValues {
  @Entry var memoraToolbarControlSize: CGFloat = 36
}
