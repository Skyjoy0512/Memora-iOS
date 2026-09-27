import SwiftUI
import UIKit

/// Presents the system share sheet for files and text.
struct ActivityView: UIViewControllerRepresentable {
  var items: [Any]
  /// Called when the sheet is finished, so a temporary export can be removed.
  var onComplete: (() -> Void)?

  func makeUIViewController(context: Context) -> UIActivityViewController {
    let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
    controller.completionWithItemsHandler = { _, _, _, _ in
      onComplete?()
    }
    return controller
  }

  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
