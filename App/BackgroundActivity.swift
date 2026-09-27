import UIKit

/// Asks the system for a little more time when the app leaves the screen, so a
/// summary that is almost written can finish instead of being cut off the
/// moment someone switches apps. The time is handed back as soon as the work
/// ends, or when the system says it is up.
@MainActor
final class BackgroundActivity {
  private var identifier = UIBackgroundTaskIdentifier.invalid

  init(name: String) {
    identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
      self?.end()
    }
  }

  func end() {
    guard identifier != .invalid else { return }
    UIApplication.shared.endBackgroundTask(identifier)
    identifier = .invalid
  }
}
