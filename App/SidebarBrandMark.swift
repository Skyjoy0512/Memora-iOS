import SwiftUI

/// The supplied sidebar lettering, drawn as-is at its own 346×65 aspect ratio.
struct SidebarBrandMark: View {
  var width: CGFloat = 120

  var body: some View {
    Image("memora-sidebar-wordmark")
      .renderingMode(.original)
      .resizable()
      .scaledToFit()
      .frame(width: width, height: height)
      .accessibilityLabel("Memora")
      .accessibilityIdentifier("sidebar.logo")
  }

  private var height: CGFloat {
    width * 65 / 346
  }
}
