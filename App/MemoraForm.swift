import SwiftUI

/// Native fields and controls on the same flat canvas as the content screens.
struct MemoraForm<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    Form {
      content()
        .listRowBackground(MemoraPalette.background)
        .listRowInsets(EdgeInsets(top: MemoraSpacing.md, leading: MemoraSpacing.screen,
          bottom: MemoraSpacing.md, trailing: MemoraSpacing.screen))
        .listRowSeparatorTint(MemoraPalette.border)
        .listSectionSeparator(.hidden)
    }
    .memoraPlainList()
    .contentMargins(.horizontal, 0, for: .scrollContent)
  }
}
