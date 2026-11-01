import SwiftUI

/// The supplied vector artwork has dedicated light and dark appearance assets.
struct SidebarBrandMark: View {
  var body: some View {
    Image("memora-sidebar-logo")
      .resizable()
      .renderingMode(.original)
      .scaledToFit()
      .frame(width: 106, height: 22)
      .accessibilityLabel("Memora")
      .accessibilityIdentifier("sidebar.logo")
  }
}
