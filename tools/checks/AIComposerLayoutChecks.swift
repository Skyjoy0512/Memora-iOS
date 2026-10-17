import Foundation

@main
struct AIComposerLayoutChecks {
  static func main() {
    precondition(!AIComposerLayoutPolicy.offersExpansion(for: ""))
    precondition(!AIComposerLayoutPolicy.offersExpansion(for: String(repeating: "あ", count: 180)))
    precondition(AIComposerLayoutPolicy.offersExpansion(for: String(repeating: "あ", count: 181)))
    let family = "👨‍👩‍👧‍👦"
    precondition(!AIComposerLayoutPolicy.offersExpansion(for: String(repeating: family, count: 180)),
      "The disclosure threshold counts characters, not UTF16 code units")
    precondition(AIComposerLayoutPolicy.offersExpansion(for: "A\nB\nC\nD"))
    precondition(AIComposerLayoutPolicy.offersExpansion(for: "A\r\nB\r\nC\r\nD"))
    precondition(!AIComposerLayoutPolicy.offersExpansion(for: "A\nB\nC"))
    precondition(AIComposerLayoutPolicy.lines(isExpanded: false, isTall: true) == 1...1)
    precondition(AIComposerLayoutPolicy.maximumTextHeight(isExpanded: false, isTall: true) == nil)
    let regular = AIComposerLayoutPolicy.maximumTextHeight(isExpanded: true, isTall: false)!
    let tall = AIComposerLayoutPolicy.maximumTextHeight(isExpanded: true, isTall: true)!
    precondition(tall > regular && tall <= 280, "Large text must leave room for keyboard and buttons")
    precondition(AIComposerLayoutPolicy.lines(isExpanded: true, isTall: true).upperBound == 11)
    precondition(AIComposerLayoutPolicy.offersExpansion(for: String(repeating: "あ", count: 1_000_000)))
    precondition(AIComposerLayoutPolicy.lines(isExpanded: true, isTall: false, lineHeight: 72) == 1...2)
    precondition(AIComposerLayoutPolicy.lines(isExpanded: true, isTall: true, lineHeight: 72) == 1...3)
    for height: CGFloat in [0, -1, .nan, .infinity, 1e-100] {
      let lines = AIComposerLayoutPolicy.lines(isExpanded: true, isTall: true, lineHeight: height)
      precondition(lines.lowerBound == 1 && lines.upperBound >= 1 && lines.upperBound <= 12)
    }
    print("AIComposerLayoutChecks: passed (Japanese/emoji character threshold, multiline/CRLF, collapsed/tall bounds, large input)")
  }
}
