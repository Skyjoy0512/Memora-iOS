import Foundation

/// Reserve before dispatch, refund only a complete provider-reported count.
/// Unknown usage and failed requests keep their reservation; neither is free.
struct AgentOutputBudget {
  static let maximumTokens = 128_000
  private(set) var chargedTokens = 0
  private var reservations: [UUID: Int] = [:]
  private(set) var isExhausted = false
  var hasPendingReservations: Bool { !reservations.isEmpty }

  mutating func reserve(maximum: Int) throws -> Reservation {
    guard maximum > 0, reservations.count < AgentSessionBudget.maximumRequests, !isExhausted,
          chargedTokens < Self.maximumTokens else { throw AIAnswerFailure.executionLimit }
    let allowance = min(maximum, Self.maximumTokens - chargedTokens)
    chargedTokens += allowance
    let reservation = Reservation(id: UUID(), maximumTokens: allowance)
    reservations[reservation.id] = allowance
    return reservation
  }

  mutating func settle(_ reservation: Reservation, reportedOutputTokens: Int?) throws {
    guard let reserved = reservations[reservation.id], reserved == reservation.maximumTokens else {
      throw AIAnswerFailure.executionLimit
    }
    reservations.removeValue(forKey: reservation.id)
    guard let actual = reportedOutputTokens, actual >= 0 else { return }
    guard actual <= reserved else {
      isExhausted = true
      throw AIAnswerFailure.executionLimit
    }
    chargedTokens -= reserved - actual
  }

  struct Reservation: Equatable {
    let id: UUID
    let maximumTokens: Int
  }
}
