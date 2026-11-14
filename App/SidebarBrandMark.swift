import SwiftUI

/// The sidebar stacks the supplied mark over its outlined wordmark. The
/// wordmark is drawn larger than in the print lockup so it stays readable at
/// the drawer header's 144pt width; its letterforms and tracking are unchanged.
struct SidebarBrandMark: View {
  var body: some View {
    VStack(spacing: 6) {
      MemoraBrandMark(width: 144)
        .accessibilityHidden(true)
      MemoraWordmark(width: 120)
        .accessibilityHidden(true)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Memora")
    .accessibilityIdentifier("sidebar.logo")
  }
}
