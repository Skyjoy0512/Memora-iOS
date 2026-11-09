import SwiftUI

/// The supplied vector artwork has dedicated light and dark appearance assets.
struct SidebarBrandMark: View {
  var body: some View {
    MemoraWordmark(width: 144)
      .accessibilityIdentifier("sidebar.logo")
  }
}
