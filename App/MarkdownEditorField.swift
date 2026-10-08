import SwiftUI
import UIKit

struct MarkdownEditorField: View {
  @Binding var markdown: String
  var font: Font
  var minHeight: CGFloat
  var isFocused: FocusState<Bool>.Binding
  var onStructure: ((MarkdownEditingAction) -> Void)?
  var allowsStructure = true

  var body: some View {
    MarkdownTextSurface(markdown: $markdown, isFocused: isFocused,
      onStructure: onStructure, allowsStructure: allowsStructure, textStyle: textStyle)
      .frame(minHeight: minHeight)
      .focused(isFocused)
  }

  private var textStyle: UIFont.TextStyle {
    if font == .title || font == .title.bold() { return .title1 }
    if font == .title2 || font == .title2.bold() { return .title2 }
    if font == .title3 || font == .title3.bold() { return .title3 }
    if font == .headline { return .headline }
    if font == .subheadline { return .subheadline }
    return .body
  }
}

private struct MarkdownTextSurface: UIViewRepresentable {
  @Binding var markdown: String
  var isFocused: FocusState<Bool>.Binding
  var onStructure: ((MarkdownEditingAction) -> Void)?
  var allowsStructure: Bool
  var textStyle: UIFont.TextStyle

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeUIView(context: Context) -> UITextView {
    let view = UITextView()
    view.backgroundColor = .clear
    view.isScrollEnabled = false
    view.adjustsFontForContentSizeCategory = true
    view.textContainerInset = .zero
    view.textContainer.lineFragmentPadding = 0
    view.delegate = context.coordinator
    view.accessibilityLabel = "本文"
    context.coordinator.installToolbar(on: view)
    return view
  }

  func updateUIView(_ view: UITextView, context: Context) {
    context.coordinator.parent = self
    if context.coordinator.lastMarkdown != markdown, view.markedTextRange == nil {
      view.attributedText = MarkdownEditingText.attributed(markdown, textStyle: textStyle)
      context.coordinator.lastMarkdown = markdown
      view.typingAttributes = [.font: UIFont.preferredFont(forTextStyle: textStyle), .foregroundColor: UIColor.label]
    }
    if isFocused.wrappedValue, !view.isFirstResponder {
      DispatchQueue.main.async {
        guard context.coordinator.parent.isFocused.wrappedValue else { return }
        view.becomeFirstResponder()
      }
    } else if !isFocused.wrappedValue, view.isFirstResponder {
      view.resignFirstResponder()
    }
  }

  func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
    guard let width = proposal.width else { return nil }
    return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
  }

  final class Coordinator: NSObject, UITextViewDelegate {
    var parent: MarkdownTextSurface
    var lastMarkdown: String?
    weak var textView: UITextView?

    init(_ parent: MarkdownTextSurface) { self.parent = parent }

    func textViewDidBeginEditing(_ textView: UITextView) { parent.isFocused.wrappedValue = true }
    func textViewDidEndEditing(_ textView: UITextView) {
      parent.isFocused.wrappedValue = false
    }
    func textViewDidChange(_ textView: UITextView) {
      let value = MarkdownEditingText.markdown(textView.attributedText)
      lastMarkdown = value
      parent.markdown = value
      textView.invalidateIntrinsicContentSize()
    }

    func installToolbar(on view: UITextView) {
      textView = view
      let toolbar = MarkdownEditingToolbar()
      toolbar.sizeToFit()
      let format = UIBarButtonItem(image: UIImage(systemName: MemoraIcon.textformat.rawValue), style: .plain, target: nil, action: nil)
      format.accessibilityLabel = "書式"
      var formatActions = [
        action("太字") { self.toggle(.traitBold) },
        action("斜体") { self.toggle(.traitItalic) }
      ]
      if parent.allowsStructure {
        formatActions += [
          action("本文") { self.structure(.paragraph) },
          action("見出し") { self.structure(.heading) }
        ]
      }
      format.menu = UIMenu(children: formatActions)
      let list = UIBarButtonItem(image: UIImage(systemName: MemoraIcon.checklist.rawValue), style: .plain, target: nil, action: nil)
      list.accessibilityLabel = "リスト"
      list.menu = UIMenu(children: [
        action("箇条書き") { self.structure(.bullet) },
        action("番号付き") { self.structure(.numbered) },
        action("チェックリスト") { self.structure(.checklist) },
        action("チェック状態を切り替える") { self.structure(.toggleCheck) }
      ])
      let table = UIBarButtonItem(image: UIImage(systemName: MemoraIcon.tablecells.rawValue), style: .plain, target: nil, action: nil)
      table.accessibilityLabel = "表"
      table.menu = UIMenu(children: [
        action("表を挿入") { self.structure(.table) },
        action("行を追加") { self.structure(.addRow) },
        action("列を追加") { self.structure(.addColumn) },
        action("この行を削除") { self.structure(.deleteRow) },
        action(parent.onStructure == nil ? "最後の列を削除" : "この列を削除") { self.structure(.deleteColumn) }
      ])
      list.isEnabled = parent.allowsStructure
      table.isEnabled = parent.allowsStructure
      let done = UIBarButtonItem(title: "完了", style: .done, target: self, action: #selector(finish))
      toolbar.items = parent.allowsStructure
        ? [format, .flexibleSpace(), list, .flexibleSpace(), table, .flexibleSpace(), done]
        : [format, .flexibleSpace(), done]
      view.inputAccessoryView = toolbar
    }

    private func action(_ title: String, handler: @escaping () -> Void) -> UIAction {
      UIAction(title: title) { _ in handler() }
    }

    @objc private func finish() {
      guard let textView, textView.markedTextRange == nil else { return }
      parent.isFocused.wrappedValue = false
      textView.resignFirstResponder()
    }

    private func toggle(_ trait: UIFontDescriptor.SymbolicTraits) {
      guard let textView, textView.markedTextRange == nil else { return }
      let range = textView.selectedRange
      if range.length == 0 {
        var attributes = textView.typingAttributes
        attributes[.font] = toggled(attributes[.font] as? UIFont, trait: trait)
        textView.typingAttributes = attributes
      } else {
        let value = NSMutableAttributedString(attributedString: textView.attributedText)
        value.enumerateAttribute(.font, in: range) { font, segment, _ in
          value.addAttribute(.font, value: self.toggled(font as? UIFont, trait: trait), range: segment)
        }
        textView.attributedText = value
        textView.selectedRange = range
        textViewDidChange(textView)
      }
    }

    private func toggled(_ font: UIFont?, trait: UIFontDescriptor.SymbolicTraits) -> UIFont {
      let font = font ?? .preferredFont(forTextStyle: parent.textStyle)
      var traits = font.fontDescriptor.symbolicTraits
      if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
      return UIFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits) ?? font.fontDescriptor, size: font.pointSize)
    }

    private func structure(_ action: MarkdownEditingAction) {
      guard parent.allowsStructure, let textView, textView.markedTextRange == nil else { return }
      textViewDidChange(textView)
      if let handler = parent.onStructure {
        handler(action)
      } else {
        let prefix = (textView.text as NSString).substring(to: min(textView.selectedRange.location, (textView.text as NSString).length))
        let line = prefix.components(separatedBy: "\n").count - 1
        let lines = parent.markdown.components(separatedBy: "\n")
        let location = lines.prefix(line).reduce(0) { $0 + ($1 as NSString).length + 1 }
        let value = MarkdownEditingAction.applying(action, to: parent.markdown,
          selection: NSRange(location: location, length: 0))
        parent.markdown = value
      }
    }
  }
}
