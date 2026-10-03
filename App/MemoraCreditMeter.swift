import Foundation
import Observation

/// The Memora Intelligence credits left, as the server last reported them on a
/// response. The server holds the real balance; this only mirrors it.
@MainActor
@Observable
final class MemoraCreditMeter {
  static let shared = MemoraCreditMeter()

  private(set) var remaining: Int?
  private(set) var updatedAt: Date?

  /// Reads the balance header from a response from Memora's server.
  nonisolated static func observe(_ response: URLResponse) {
    guard let http = response as? HTTPURLResponse,
          let value = http.value(forHTTPHeaderField: "X-Memora-Credits-Remaining"),
          let credits = Int(value) else { return }
    Task { @MainActor in
      shared.remaining = credits
      shared.updatedAt = .now
    }
  }
}
