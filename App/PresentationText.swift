import CoreText
import Foundation

enum PresentationText {
  static func widestLine(_ element: PresentationElement) -> Double {
    return lines(element).map { text in
      CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed(text, element: element)), nil, nil, nil)
    }.max() ?? 0
  }

  static func font(size: Double, bold: Bool, name: String = PresentationTheme.font) -> CTFont {
    let font = CTFontCreateWithName(name as CFString, size, nil)
    return bold ? CTFontCreateCopyWithSymbolicTraits(font, size, nil, .traitBold, .traitBold) ?? font : font
  }

  static func attributed(_ text: String, element: PresentationElement) -> NSAttributedString {
    let key = NSAttributedString.Key(kCTFontAttributeName as String)
    let result = NSMutableAttributedString(string: text, attributes: [key: font(size: element.fontSize, bold: element.bold, name: element.fontName)])
    if let latin = element.latinFontName, latin != element.fontName {
      let face = font(size: element.fontSize, bold: element.bold, name: latin)
      var offset = 0
      for character in text {
        let count = String(character).utf16.count
        if character.unicodeScalars.allSatisfy({ $0.value < 128 }) { result.addAttribute(key, value: face, range: NSRange(location: offset, length: count)) }
        offset += count
      }
    }
    return result
  }

  static func lines(_ element: PresentationElement) -> [String] {
    return element.text.components(separatedBy: .newlines).flatMap { paragraph -> [String] in
      guard !paragraph.isEmpty else { return [""] }
      let source = paragraph as NSString
      let typesetter = CTTypesetterCreateWithAttributedString(attributed(paragraph, element: element))
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
