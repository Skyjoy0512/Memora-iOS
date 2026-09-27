import SwiftUI

/// Every segmented switch in the app: the system control, which draws and
/// morphs the selection pill, on a Liquid Glass capsule — the same surface as
/// the floating tab bar, so switches read alike on every screen.
struct GlassSegmentedPicker<Item: Hashable>: View {
  var items: [Item]
  @Binding var selection: Item
  var title: (Item) -> String

  var body: some View {
    let control = GlassSegmentedControl(items: items, selection: $selection, title: title)
    if #available(iOS 26.0, *) {
      control.glassEffect(.regular, in: .capsule)
    } else {
      control
        .background(.regularMaterial, in: Capsule())
        .overlay {
          Capsule().stroke(Color(uiColor: .separator).opacity(0.6), lineWidth: 0.5)
        }
    }
  }
}
