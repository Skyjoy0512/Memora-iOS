import SwiftUI

/// A plain back control that never shows the previous screen's title, so a
/// pushed screen does not read as its parent. The name matches the app's other
/// back control.
struct MemoraBackButton: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    Button("1つ前に戻る", icon: .chevronLeft) {
      dismiss()
    }
    .labelStyle(.iconOnly)
  }
}

extension View {
  /// Replaces the system back button — which would otherwise carry the previous
  /// screen's title — with a plain one.
  func memoraBackButton() -> some View {
    navigationBarBackButtonHidden(true)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          MemoraBackButton()
        }
      }
  }
}
