import Foundation

/// The screens after the introduction, in order.
enum CallSetupStep: Hashable {
  case explanation
  case phoneNumber
  case verification(String)
  case verified
  case contacts
}
