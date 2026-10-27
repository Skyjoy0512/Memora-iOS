import CoreText
import Foundation

enum PresentationText {
  static func font(size: Double, bold: Bool) -> CTFont {
    let font = CTFontCreateWithName(PresentationTheme.font as CFString, size, nil)
    return bold ? CTFontCreateCopyWithSymbolicTraits(font, size, nil, .traitBold, .traitBold) ?? font : font
  }

  static func lines(_ element: PresentationElement) -> [String] {
    let font = font(size: element.fontSize, bold: element.bold)
    return element.text.components(separatedBy: .newlines).flatMap { paragraph -> [String] in
      guard !paragraph.isEmpty else { return [""] }
      let source = paragraph as NSString
      let typesetter = CTTypesetterCreateWithAttributedString(NSAttributedString(string: paragraph,
        attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
      var result: [String] = [], offset = 0
      while offset < source.length {
        let count = max(1, CTTypesetterSuggestLineBreak(typesetter, offset, max(1, element.width * 0.94)))
        let range = source.rangeOfComposedCharacterSequences(for: NSRange(location: offset, length: min(count, source.length - offset)))
        result.append(source.substring(with: range)); offset = NSMaxRange(range)
      }
      return result
    }
  }
}
