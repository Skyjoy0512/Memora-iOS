import SwiftUI

struct MemoraSettingsPage: ViewModifier {
  var title: String

  func body(content: Content) -> some View {
    content
      .memoraPlainList()
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
  }
}

extension View {
  func memoraSettingsPage(_ title: String) -> some View {
    modifier(MemoraSettingsPage(title: title))
  }
}
