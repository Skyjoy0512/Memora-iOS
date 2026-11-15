import Foundation

/// Features that are built but held back from the screen.
enum FeatureFlags {
  // Keep the optional image preview out of the reading flow until it is wanted again.
  static let isInlineSummaryPosterEnabled = false

  /// Calling is held back until it works between Memora users inside the app
  /// (WebRTC, no phone line). The screens and the call record path stay in
  /// place; turning this on brings back ＋ › 電話をかける and its previews.
  static let isCallingEnabled = false

  /// Live conversation is built but only compiled into explicitly enabled
  /// debug builds. Both DEBUG and MEMORA_ENABLE_LIVE_CONVERSATION are required;
  /// ordinary Debug and Release builds keep it disabled with no runtime switch.
  #if DEBUG && MEMORA_ENABLE_LIVE_CONVERSATION
  static let isLiveConversationEnabled = true
  #else
  static let isLiveConversationEnabled = false
  #endif
}
