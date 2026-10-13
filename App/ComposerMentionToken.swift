import Foundation

struct ComposerMentionToken: Equatable {
  var range: NSRange
  var query: String

  static func parse(text: String, selection: NSRange, hasMarkedText: Bool) -> Self? {
    guard !hasMarkedText, selection.length == 0,
          let cursor = Range(selection, in: text)?.lowerBound else { return nil }
    var start = cursor
    while start > text.startIndex {
      let previous = text.index(before: start)
      let character = text[previous]
      if character == "@" {
        if previous > text.startIndex {
          let preceding = text[text.index(before: previous)]
          guard preceding.isWhitespace || "(（「『".contains(preceding) else { return nil }
        }
        var end = cursor
        while end < text.endIndex, isQueryCharacter(text[end]) { end = text.index(after: end) }
        return Self(range: NSRange(previous..<end, in: text), query: String(text[start..<cursor]))
      }
      guard isQueryCharacter(character) else { return nil }
      start = previous
    }
    return nil
  }

  private static func isQueryCharacter(_ character: Character) -> Bool {
    !character.isWhitespace && !"@[]()（）「」『』、。,:;/\\".contains(character)
  }
}
