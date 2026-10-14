import Foundation

/// The scene, delegate and foreground intents share the same model in their
/// host process; an intent never constructs a second stale record array.
@MainActor
final class MemoraAppRuntime {
  static let shared = MemoraAppRuntime()
  let model = MemoraModel()
  private init() {}
}
