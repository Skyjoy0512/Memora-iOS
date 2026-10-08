import UIKit

enum MarkdownEditingText {
  static func attributed(_ markdown: String, textStyle: UIFont.TextStyle = .body) -> NSAttributedString {
    let parsed = InlineMarkdownEditor.attributed(markdown)
    let result = NSMutableAttributedString(string: "")
    for run in parsed.runs {
      let intent = run.inlinePresentationIntent ?? []
      var traits: UIFontDescriptor.SymbolicTraits = []
      if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
      if intent.contains(.emphasized) { traits.insert(.traitItalic) }
      let base = intent.contains(.code) ? UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: textStyle).pointSize, weight: .regular) : UIFont.preferredFont(forTextStyle: textStyle)
      let font = UIFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits) ?? base.fontDescriptor, size: base.pointSize)
      var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.label]
      if let link = run.link { attributes[.link] = link }
      if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
      result.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
    }
    return result
  }

  static func markdown(_ value: NSAttributedString) -> String {
    var result = ""
    value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) { attributes, range, _ in
      var text = (value.string as NSString).substring(with: range)
      let font = attributes[.font] as? UIFont
      let traits = font?.fontDescriptor.symbolicTraits ?? []
      if traits.contains(.traitMonoSpace) { text = "`\(text)`" }
      else {
        if traits.contains(.traitItalic) { text = "*\(text)*" }
        if traits.contains(.traitBold) { text = "**\(text)**" }
        if attributes[.strikethroughStyle] != nil { text = "~~\(text)~~" }
      }
      if let link = attributes[.link] as? URL { text = "[\(text)](\(link.absoluteString))" }
      result += text
    }
    return result
  }
}
