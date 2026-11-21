import SwiftUI

/// Keep search guidance above the keyboard, without a full-height empty canvas.
struct ToolsSearchEmptyState: View {
  var scopeName: String
  var broadenSearch: (() -> Void)?
  var clear: () -> Void
  var body: some View {
    CollectionSearchState(title: "一致する項目がありません", message: "検索範囲：\(scopeName)",
      clear: broadenSearch ?? clear, clearTitle: broadenSearch == nil ? "検索語を消去" : "すべてのカテゴリで検索")
      .accessibilityIdentifier("tools.empty")
  }
}
