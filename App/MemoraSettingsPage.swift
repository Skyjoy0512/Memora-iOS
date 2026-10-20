import SwiftUI

struct MemoraSettingsPage: ViewModifier {
  var title: String

  func body(content: Content) -> some View {
    content
      .scrollContentBackground(.hidden)
      .background(Color(uiColor: .systemGroupedBackground))
      .contentMargins(.horizontal, MemoraSpacing.screen, for: .scrollContent)
      .listSectionSpacing(MemoraSpacing.xxl)
      .environment(\.defaultMinListRowHeight, 56)
      .textCase(nil)
      .tint(MemoraPalette.textPrimary)
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
  }
}

extension View {
  func memoraSettingsPage(_ title: String) -> some View {
    modifier(MemoraSettingsPage(title: title))
  }
}
