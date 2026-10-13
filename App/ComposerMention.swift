import Foundation

struct ComposerMention: Identifiable, Codable, Equatable {
  var id = UUID()
  var pluginID: String
  var label: String
  var range: NSRange
  var token: String { "[@\(label)]" }

  func isValid(in text: String) -> Bool {
    guard let bounds = Range(range, in: text) else { return false }
    return text[bounds] == token
  }

  static func reconciled(_ mentions: [Self], from old: String, to new: String) -> [Self] {
    let before = Array(old.utf16), after = Array(new.utf16)
    var prefix = 0
    while prefix < min(before.count, after.count), before[prefix] == after[prefix] { prefix += 1 }
    var suffix = 0
    while suffix < min(before.count, after.count) - prefix,
          before[before.count - suffix - 1] == after[after.count - suffix - 1] { suffix += 1 }
    let end = before.count - suffix
    let delta = after.count - before.count
    return mentions.compactMap { mention in
      var updated = mention
      if end <= mention.range.location {
        updated.range.location += delta
      } else if prefix < NSMaxRange(mention.range) { return nil }
      return updated.isValid(in: new) ? updated : nil
    }
  }
}
