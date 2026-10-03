import Foundation

/// The telephony behind calls placed from Memora. A call is carried over the
/// internet by a calling provider (for example Twilio Voice) and bridged to the
/// phone network, so its audio passes through the app and can be transcribed
/// on the device — which iOS does not allow for ordinary phone calls. The app
/// reaches the provider only through this protocol; a server issues the access
/// tokens and verifies the caller ID.
protocol CallingService: Sendable {
  /// Starts verifying that the person owns `phoneNumber` (E.164): the provider
  /// calls it and the person enters the returned code on the keypad.
  func startCallerVerification(phoneNumber: String) async throws -> CallerVerification
  /// Whether the number has been verified and can be shown as the caller ID.
  func isVerified(phoneNumber: String) async throws -> Bool
  /// Places a call from the verified number.
  func placeCall(to number: String, from callerID: String) async throws -> PhoneCallSession
}
