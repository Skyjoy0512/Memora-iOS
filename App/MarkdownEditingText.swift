import UIKit

enum MarkdownEditingText {
  static func typingAttributes(textStyle: UIFont.TextStyle) -> [NSAttributedString.Key: Any] {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = UIFontMetrics(forTextStyle: .body).scaledValue(for: MemoraTypography.readingLineSpacing)
    var font = UIFont.preferredFont(forTextStyle: textStyle)
    if textStyle == .title2 || textStyle == .title3 {
      font = UIFont.systemFont(ofSize: font.pointSize, weight: .semibold)
    }
    return [.font: font, .foregroundColor: UIColor.label, .paragraphStyle: paragraph]
  }

  static func attributed(_ markdown: String, textStyle: UIFont.TextStyle = .body) -> NSAttributedString {
    let parsed = InlineMarkdownEditor.attributed(markdown)
    let result = NSMutableAttributedString(string: "")
    for run in parsed.runs {
      let intent = run.inlinePresentationIntent ?? []
      var traits: UIFontDescriptor.SymbolicTraits = []
      if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
      if intent.contains(.emphasized) { traits.insert(.traitItalic) }
      let baseAttributes = typingAttributes(textStyle: textStyle)
      let base = intent.contains(.code) ? UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: textStyle).pointSize, weight: .regular) : (baseAttributes[.font] as? UIFont ?? UIFont.preferredFont(forTextStyle: textStyle))
      let font = UIFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits) ?? base.fontDescriptor, size: base.pointSize)
      var attributes = baseAttributes
      attributes[.font] = font
      if let link = run.link { attributes[.link] = link }
      if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
      result.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
    }
    return result
  }

  static func markdown(_ value: NSAttributedString) -> String {
    var spans: [Span] = []
    value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) { attributes, range, _ in
      let text = (value.string as NSString).substring(with: range)
      let font = attributes[.font] as? UIFont
      let traits = (font?.fontDescriptor.symbolicTraits ?? []).intersection([.traitBold, .traitItalic, .traitMonoSpace])
      let span = Span(text: text, traits: traits, strikethrough: attributes[.strikethroughStyle] != nil,
        link: attributes[.link] as? URL)
      // IME spelling/selection attributes can split one formatted word into many
      // runs. Markdown markers describe semantic formatting, not those runs.
      if let last = spans.last, last.traits == span.traits, last.strikethrough == span.strikethrough, last.link == span.link {
        spans[spans.count - 1].text += span.text
      } else { spans.append(span) }
    }
    return spans.map { span in
      var text = span.text
      if span.traits.contains(.traitMonoSpace) { text = "`\(text)`" }
      else {
        if span.traits.contains(.traitItalic) { text = "*\(text)*" }
        if span.traits.contains(.traitBold) { text = "**\(text)**" }
        if span.strikethrough { text = "~~\(text)~~" }
      }
      if let link = span.link { text = "[\(text)](\(link.absoluteString))" }
      return text
    }.joined()
  }

  private struct Span {
    var text: String
    var traits: UIFontDescriptor.SymbolicTraits
    var strikethrough: Bool
    var link: URL?
  }
}
