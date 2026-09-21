import Foundation

/// Keeps the text someone is still writing, so a draft survives leaving the
/// screen or the app being stopped before it is saved.
@MainActor
enum DraftStore {
  private static let prefix = "draft."

  static func load(_ key: String) -> String? {
    guard let data = LocalStore.shared.read(prefix + key),
          let text = String(data: data, encoding: .utf8) else {
      return nil
    }
    return text
  }

  static func save(_ text: String, key: String) {
    try? LocalStore.shared.write(prefix + key, data: Data(text.utf8))
  }

  static func clear(_ key: String) {
    try? LocalStore.shared.remove(prefix + key)
  }
}
