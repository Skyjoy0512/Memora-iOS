import EventKitUI
import SwiftUI

/// EventKit's editor owns recurrence choices, explicit save/delete, and its
/// native validation/recovery. A missing event must never become a new event.
struct CalendarEventEditor: UIViewControllerRepresentable {
  var editing: CalendarEventEditContext
  var onFinish: () -> Void
  var onUnavailable: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

  func makeUIViewController(context: Context) -> UIViewController {
    guard editing.isEditable else {
      Task { @MainActor in onUnavailable() }
      return UIViewController()
    }
    let controller = EKEventEditViewController()
    controller.eventStore = editing.store
    controller.event = editing.event
    controller.editViewDelegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ controller: UIViewController, context: Context) {}

  static func dismantleUIViewController(_ controller: UIViewController, coordinator: Coordinator) {
    if !coordinator.finished { (controller as? EKEventEditViewController)?.cancelEditing() }
  }

  @MainActor final class Coordinator: NSObject, EKEventEditViewDelegate {
    var finished = false
    var onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

    nonisolated func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
      // EventKitUI's legacy delegate is nonisolated. Never move its controller
      // across actors; only finish the SwiftUI state on the main actor.
      Task { @MainActor [weak self] in
        guard let self, !self.finished else { return }
        self.finished = true
        self.onFinish()
      }
    }
  }
}
