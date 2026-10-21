import SwiftUI

/// One row rhythm for collections, pickers and editing screens.
struct MemoraList<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    List {
      content()
        .listRowBackground(MemoraPalette.background)
        .listRowInsets(EdgeInsets(top: MemoraSpacing.md, leading: MemoraSpacing.screen,
          bottom: MemoraSpacing.md, trailing: MemoraSpacing.screen))
        .listRowSeparatorTint(MemoraPalette.border)
        .listSectionSeparator(.hidden)
    }
    .memoraPlainList()
  }
}
