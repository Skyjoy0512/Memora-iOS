import Foundation

/// A tool the model asked to run, with its arguments as decoded JSON.
struct AgentToolCall {
  var id: String
  var name: String
  var arguments: [String: Any]

  func string(_ key: String) -> String {
    (arguments[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  func strings(_ key: String) -> [String] {
    (arguments[key] as? [Any])?
      .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty } ?? []
  }

  func objects(_ key: String) -> [[String: Any]] {
    arguments[key] as? [[String: Any]] ?? []
  }

  func bool(_ key: String) -> Bool {
    arguments[key] as? Bool ?? false
  }

  func int(_ key: String) -> Int? {
    if let value = arguments[key] as? Int { return value }
    if let value = arguments[key] as? Double { return Int(exactly: value) }
    return nil
  }
}
