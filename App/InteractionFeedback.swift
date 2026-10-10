import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class InteractionFeedback {
  static let shared = InteractionFeedback()
  static let settingsKey = "memora.haptics.enabled"

  enum Kind: Equatable {
    case tap
    case selection
    case success
    case error

    var sensoryFeedback: SensoryFeedback {
      switch self {
      case .tap: .impact(weight: .light, intensity: 0.65)
      case .selection: .selection
      case .success: .success
      case .error: .error
      }
    }
  }

  struct Event: Equatable {
    var sequence: UInt64
    var kind: Kind
  }

  private(set) var event: Event?
  @ObservationIgnored private var sequence: UInt64 = 0
  @ObservationIgnored private var lastSentAt: ContinuousClock.Instant?
  @ObservationIgnored private var defaults: UserDefaults
  @ObservationIgnored private var isActive: @MainActor () -> Bool
  @ObservationIgnored private var isCapturingAudio: @MainActor () -> Bool
  @ObservationIgnored private var now: @MainActor () -> ContinuousClock.Instant

  init(
    defaults: UserDefaults = .standard,
    isActive: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active },
    isCapturingAudio: @escaping @MainActor () -> Bool = {
      switch AudioSessionCoordinator.shared.owner {
      case .recording, .speechInput, .voiceEnrollment: true
      case .playback, nil: false
      }
    },
    now: @escaping @MainActor () -> ContinuousClock.Instant = { .now }
  ) {
    self.defaults = defaults
    self.isActive = isActive
    self.isCapturingAudio = isCapturingAudio
    self.now = now
  }

  var canPlay: Bool {
    (defaults.object(forKey: Self.settingsKey) as? Bool ?? true)
      && isActive() && !isCapturingAudio()
  }

  func send(_ kind: Kind) {
    guard canPlay else { return }
    let instant = now()
    if let lastSentAt, lastSentAt.duration(to: instant) < .milliseconds(90) { return }
    lastSentAt = instant
    sequence &+= 1
    event = Event(sequence: sequence, kind: kind)
  }
}
