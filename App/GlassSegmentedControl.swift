import SwiftUI
import UIKit

/// A title-only segmented control that sits on the Liquid Glass layer, so the
/// section switch matches the floating tab bar. `UISegmentedControl` draws the
/// selection pill and its morph; the glass capsule is added by the caller.
struct GlassSegmentedControl<Item: Hashable>: UIViewRepresentable {
  var items: [Item]
  @Binding var selection: Item
  var title: (Item) -> String
  /// A little taller than the system default, which the section switch wants.
  var height: CGFloat = 36

  func makeUIView(context: Context) -> UISegmentedControl {
    let control = UISegmentedControl()
    for (index, item) in items.enumerated() {
      control.insertSegment(withTitle: title(item), at: index, animated: false)
    }
    control.selectedSegmentIndex = items.firstIndex(of: selection) ?? UISegmentedControl.noSegment
    control.selectedSegmentTintColor = UIColor.secondarySystemFill
    control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
    return control
  }

  func updateUIView(_ control: UISegmentedControl, context: Context) {
    context.coordinator.parent = self
    // Never move the selection while a finger is down: doing so cancels the
    // touch in progress, which is what swallowed the first tap.
    guard !control.isTracking, let index = items.firstIndex(of: selection) else { return }
    if control.selectedSegmentIndex != index {
      control.selectedSegmentIndex = index
    }
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize,
    uiView: UISegmentedControl,
    context: Context
  ) -> CGSize? {
    CGSize(width: proposal.replacingUnspecifiedDimensions().width, height: height)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  @MainActor
  final class Coordinator: NSObject {
    var parent: GlassSegmentedControl
    init(parent: GlassSegmentedControl) {
      self.parent = parent
    }

    @objc func changed(_ control: UISegmentedControl) {
      let items = parent.items
      guard items.indices.contains(control.selectedSegmentIndex) else { return }
      if parent.selection != items[control.selectedSegmentIndex] {
        InteractionFeedback.shared.send(.selection)
      }
      parent.selection = items[control.selectedSegmentIndex]
    }
  }
}
