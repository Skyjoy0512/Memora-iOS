import Foundation
import UIKit

extension MemoraModel {
  /// Shows the offer for one deletion, finalizing whatever offer it replaces.
  func scheduleUndo(_ action: UndoAction) {
    finalizePendingUndo()
    pendingUndo = action
    undoDismissTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(Self.undoDisplaySeconds))
      guard let self, !Task.isCancelled else { return }
      self.finalizePendingUndo()
    }
  }

  /// Longer with an assistive technology, where five seconds is too short to
  /// reach the button.
  private static var undoDisplaySeconds: TimeInterval {
    UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning ? 10 : 5
  }

  /// Takes the offer back: the record returns and no file is removed.
  func performPendingUndo() {
    undoDismissTask?.cancel()
    undoDismissTask = nil
    let action = pendingUndo
    pendingUndo = nil
    action?.undo()
  }

  /// Passes over the offer, running its delayed work such as a file removal.
  func finalizePendingUndo() {
    undoDismissTask?.cancel()
    undoDismissTask = nil
    guard let action = pendingUndo else { return }
    pendingUndo = nil
    action.finalize()
  }
}
