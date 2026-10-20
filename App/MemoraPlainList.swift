import SwiftUI

extension View {
  func memoraPlainList() -> some View {
    modifier(MemoraPlainList())
  }
}

private struct MemoraPlainList: ViewModifier {
  func body(content: Content) -> some View {
    content
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .background(MemoraPalette.background)
      .contentMargins(.top, MemoraSpacing.sm, for: .scrollContent)
      .listSectionSpacing(MemoraSpacing.xxl)
      .environment(\.defaultMinListRowHeight, 52)
      .headerProminence(.increased)
      .textCase(nil)
      .tint(MemoraPalette.textPrimary)
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(MemoraPalette.background, for: .navigationBar)
  }
}
