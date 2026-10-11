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
  private(set) var authenticationMessage: String?
  private(set) var isAuthenticating = false

  @ObservationIgnored private var backgroundedAt: Date?
  @ObservationIgnored private var authentication: @MainActor () async throws -> Bool
  @ObservationIgnored private var lockEnabled: @MainActor () -> Bool

  init(authentication: @escaping @MainActor () async throws -> Bool = AppLockService.authenticateOwner,
       lockEnabled: @escaping @MainActor () -> Bool = { AppLockService.isEnabled }) {
    self.authentication = authentication
    self.lockEnabled = lockEnabled
  }

  static var isEnabled: Bool {
    UserDefaults.standard.bool(forKey: enabledKey)
  }

  /// Locks at launch, when the setting is on.
  func lockIfEnabled() {
    guard lockEnabled() else { return }
    isLocked = true
  }

  func handleScenePhase(_ phase: ScenePhase, isRecording: Bool) {
    switch phase {
    case .inactive:
      // Mask immediately, so the app switcher never shows the content.
      if lockEnabled() || isLocked { isCovered = true }
    case .background:
      backgroundedAt = .now
      if lockEnabled() || isLocked { isCovered = true }
    case .active:
      isCovered = false
      guard lockEnabled(), !isRecording else {
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
    authenticationMessage = nil
    defer { isAuthenticating = false }

    do {
      if try await authentication() {
        isLocked = false
      } else {
        authenticationMessage = "認証できませんでした。もう一度お試しください。"
      }
    } catch {
      authenticationMessage = Self.message(for: error)
    }
  }

  static func availabilityMessage() -> String? {
    let context = LAContext()
    var error: NSError?
    return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
      ? nil : message(for: error)
  }

  private static func authenticateOwner() async throws -> Bool {
    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
      throw error ?? NSError(domain: LAError.errorDomain, code: LAError.Code.authenticationFailed.rawValue)
    }
    return try await context.evaluatePolicy(
      .deviceOwnerAuthentication,
      localizedReason: "Memoraのロックを解除します。"
    )
  }

  private static func message(for error: Error?) -> String {
    guard let error = error as? LAError else {
      return "認証を開始できませんでした。ロックは解除していません。もう一度お試しください。"
    }
    switch error.code {
    case .passcodeNotSet:
      return "iPhoneの「設定」でパスコードを設定してから、もう一度お試しください。ロックは解除していません。"
    case .biometryLockout:
      return "生体認証を一時的に利用できません。パスコードで認証するか、時間をおいてもう一度お試しください。"
    case .userCancel, .appCancel, .systemCancel:
      return "認証を中止しました。ロックを解除するには、もう一度認証してください。"
    default:
      return "認証できませんでした。ロックは解除していません。もう一度お試しください。"
    }
  }
}
