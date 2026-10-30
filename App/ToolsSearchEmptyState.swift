import SwiftUI

/// Keep search guidance above the keyboard, without a full-height empty canvas.
struct ToolsSearchEmptyState: View {
  var clear: () -> Void
  var body: some View {
    CollectionSearchState(title: "見つかりません", message: "検索語を変えるか、別の分類を選んでください。", clear: clear)
      .accessibilityIdentifier("tools.empty")
  }
}
