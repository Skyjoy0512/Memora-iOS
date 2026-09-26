import Foundation
import LocalAuthentication
import Observation
import SwiftUI

/// Optional Face ID (or passcode) lock for the whole app. It hides the content
/// as soon as the app leaves the foreground, and asks for authentication when it
/// comes back — at launch, and after a longer stay in the background. It never
/// locks while a recording is running, so the recording sheet stays usable.
@MainActor
@Observable
final class AppLockService {
  static let enabledKey = "memora.appLock"
  /// Longer than this in the background, and coming back asks once more.
  static let relockAfter: TimeInterval = 5 * 60

  /// The lock screen is up and the content must stay hidden.
  private(set) var isLocked = false
  /// Content is covered without a lock screen, e.g. in the app switcher.
  private(set) var isCovered = false

  @ObservationIgnored private var backgroundedAt: Date?
  @ObservationIgnored private var isAuthenticating = false

  static var isEnabled: Bool {
    UserDefaults.standard.bool(forKey: enabledKey)
  }

  /// Locks at launch, when the setting is on.
  func lockIfEnabled() {
    guard Self.isEnabled else { return }
    isLocked = true
  }

  func handleScenePhase(_ phase: ScenePhase, isRecording: Bool) {
    switch phase {
    case .inactive:
      // Mask immediately, so the app switcher never shows the content.
      if Self.isEnabled || isLocked { isCovered = true }
    case .background:
      backgroundedAt = .now
      if Self.isEnabled || isLocked { isCovered = true }
    case .active:
      isCovered = false
      guard Self.isEnabled, !isRecording else {
        backgroundedAt = nil
        return
      }
      if isLocked {
        return
      }
      if let backgroundedAt, Date.now.timeIntervalSince(backgroundedAt) >= Self.relockAfter {
        isLocked = true
      }
      backgroundedAt = nil
    @unknown default:
      break
    }
  }

  /// Asks for authentication and lifts the lock when it succeeds.
  func unlock() async {
    guard isLocked, !isAuthenticating else { return }
    isAuthenticating = true
    defer { isAuthenticating = false }

    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
      // No biometrics or passcode set: do not trap the person out of their app.
      isLocked = false
      return
    }
    do {
      let ok = try await context.evaluatePolicy(
        .deviceOwnerAuthentication,
        localizedReason: "Memoraのロックを解除します。"
      )
      if ok { isLocked = false }
    } catch {
      // A cancelled or failed attempt leaves the lock in place.
    }
  }
}
