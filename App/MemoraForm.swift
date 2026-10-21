import SwiftUI

/// Native fields and controls on the same flat canvas as the content screens.
struct MemoraForm<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    MemoraList(content: content)
  }
}
