import Foundation

/// Stands in until a calling provider is connected. It refuses every request
/// with a reason instead of pretending a call or a verification happened.
struct UnconfiguredCallingService: CallingService {
  func startCallerVerification(phoneNumber: String) async throws -> CallerVerification {
    throw CallingError.notConfigured
  }

  func isVerified(phoneNumber: String) async throws -> Bool {
    throw CallingError.notConfigured
  }

  func placeCall(to number: String, from callerID: String) async throws -> PhoneCallSession {
    throw CallingError.notConfigured
  }
}
