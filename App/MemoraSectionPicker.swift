import SwiftUI

/// A shared content-level section selector; floating navigation owns glass.
struct MemoraSectionPicker<Item: Hashable>: View {
  var items: [Item]
  @Binding var selection: Item
  var title: (Item) -> String
  /// Set on a row that has to hold more titles than the default measure fits.
  var compact = false

  var body: some View {
    MemoraTextTabBar(items: items, selection: $selection, horizontalPadding: 0,
                     title: title, compact: compact)
  }
}
