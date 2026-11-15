import Foundation

@main
struct LiveFlagChecks {
  static func main() {
    #if DEBUG && MEMORA_ENABLE_LIVE_CONVERSATION
    precondition(FeatureFlags.isLiveConversationEnabled)
    #else
    precondition(!FeatureFlags.isLiveConversationEnabled)
    #endif
    print("LiveFlagChecks: passed")
  }
}
