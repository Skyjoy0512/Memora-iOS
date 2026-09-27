import Foundation

/// Which AI writes one summary: whatever settings say, the on-device model, or
/// one of the models the person registered for Ask AI (their DeepSeek key, say).
enum SummaryEngineChoice: Hashable {
  case settings
  case onDevice
  case registered(UUID)
}
