import SwiftUI

/// A shared content-level section selector; floating navigation owns glass.
struct MemoraSectionPicker<Item: Hashable>: View {
  var items: [Item]
  @Binding var selection: Item
  var title: (Item) -> String

  var body: some View {
    MemoraTextTabBar(items: items, selection: $selection, horizontalPadding: 0, title: title)
  }
}
