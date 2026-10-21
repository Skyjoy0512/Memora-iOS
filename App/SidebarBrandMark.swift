import SwiftUI

/// The supplied vector artwork has dedicated light and dark appearance assets.
struct SidebarBrandMark: View {
  var body: some View {
    Image("memora-sidebar-logo")
      .resizable()
      .renderingMode(.original)
      .scaledToFit()
      .frame(width: 132, height: 27)
      .accessibilityLabel("Memora")
      .accessibilityIdentifier("sidebar.logo")
  }
}
