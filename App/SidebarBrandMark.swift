import SwiftUI

/// The supplied vector artwork has dedicated light and dark appearance assets.
struct SidebarBrandMark: View {
  var body: some View {
    MemoraWordmark()
      .accessibilityIdentifier("sidebar.logo")
  }
}
