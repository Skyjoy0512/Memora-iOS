import SwiftUI
import UIKit

/// Candidate and chip taps belong to the editing session, even outside the field.
struct ComposerFocusRegion: UIViewRepresentable {
  @MainActor private static let regions = NSHashTable<UIView>.weakObjects()

  func makeUIView(context: Context) -> UIView {
    let view = UIView()
    view.isUserInteractionEnabled = false
    Self.regions.add(view)
    return view
  }

  func updateUIView(_ view: UIView, context: Context) {}

  static func contains(_ touch: UITouch) -> Bool {
    regions.allObjects.contains { region in
      guard let window = region.window, window === touch.window,
            !region.isHidden, region.alpha > 0 else { return false }
      return region.bounds.contains(touch.location(in: region))
    }
  }
}

extension View {
  func preservesComposerFocus() -> some View {
    background(ComposerFocusRegion())
  }
}
