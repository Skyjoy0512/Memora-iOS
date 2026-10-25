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
    if font == .title2 || font == .title2.bold() || font == MemoraTypography.heading(1) { return .title2 }
    if font == .title3 || font == .title3.bold() || font == MemoraTypography.heading(2) { return .title3 }
    if font == .headline { return .headline }
    if font == MemoraTypography.body.weight(.semibold) { return .headline }
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
    let category = view.traitCollection.preferredContentSizeCategory
    if (context.coordinator.lastMarkdown != markdown || context.coordinator.category != category), view.markedTextRange == nil {
      context.coordinator.isApplyingExternalUpdate = true
      defer { context.coordinator.isApplyingExternalUpdate = false }
      let selection = view.selectedRange
      view.attributedText = MarkdownEditingText.attributed(markdown, textStyle: textStyle)
      let location = min(selection.location, view.attributedText.length)
      view.selectedRange = NSRange(location: location, length: min(selection.length, view.attributedText.length - location))
      context.coordinator.lastMarkdown = markdown
      context.coordinator.category = category
      view.typingAttributes = MarkdownEditingText.typingAttributes(textStyle: textStyle)
    }
    if isFocused.wrappedValue, !view.isFirstResponder {
      DispatchQueue.main.async {
        guard context.coordinator.parent.isFocused.wrappedValue, view.window != nil else { return }
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
    var category: UIContentSizeCategory?
    var isApplyingExternalUpdate = false
    var wasComposing = false
    weak var textView: UITextView?

    init(_ parent: MarkdownTextSurface) { self.parent = parent }

    func textViewDidBeginEditing(_ textView: UITextView) { parent.isFocused.wrappedValue = true }
    func textViewDidEndEditing(_ textView: UITextView) {
      publishCommittedText(textView)
      parent.isFocused.wrappedValue = false
    }
    func textViewDidChange(_ textView: UITextView) {
      // Marked text belongs to UIKit until conversion commits. Publishing it
      // could make SwiftUI replace the editor or interpret Return as a new block.
      guard textView.markedTextRange == nil else { wasComposing = true; return }
      wasComposing = false
      publishCommittedText(textView)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
      // Some input methods unmark during a selection change without another
      // text-change callback. Flush that committed value exactly once as well.
      guard textView.isFirstResponder else { return }
      guard textView.markedTextRange == nil else { wasComposing = true; return }
      guard wasComposing else { return }
      wasComposing = false
      publishCommittedText(textView)
    }

    private func publishCommittedText(_ textView: UITextView) {
      guard !isApplyingExternalUpdate, textView.markedTextRange == nil else { return }
      let value = MarkdownEditingText.markdown(textView.attributedText)
      guard lastMarkdown != value else { return }
      lastMarkdown = value
      parent.markdown = value
      textView.invalidateIntrinsicContentSize()
    }

    func installToolbar(on view: UITextView) {
      textView = view
      let bold = button("太字", artwork: .editorBold) { self.toggle(.traitBold) }
      let italic = button("斜体", artwork: .editorItalic) { self.toggle(.traitItalic) }
      let done = button("完了", title: "完了") { self.finish() }
      done.tintColor = .systemBlue
      if parent.allowsStructure {
        let formatting = [
          button("本文", artwork: .editorBody) { self.structure(.paragraph) },
          button("見出し", artwork: .editorHeading) { self.structure(.heading) },
          bold, italic,
          button("箇条書き", artwork: .editorList) { self.structure(.bullet) },
          button("番号付き", artwork: .editorList) { self.structure(.numbered) },
          button("チェックリスト", artwork: .editorChecklist) { self.structure(.checklist) }
        ]
        let table = [
          button("チェック状態を切り替える", artwork: .editorCheck) { self.structure(.toggleCheck) },
          button("表を挿入", artwork: .editorTable) { self.structure(.table) },
          button("行を追加", title: "行＋") { self.structure(.addRow) },
          button("列を追加", title: "列＋") { self.structure(.addColumn) },
          button("この行を削除", title: "行−") { self.structure(.deleteRow) },
          button(parent.onStructure == nil ? "最後の列を削除" : "この列を削除", title: "列−") { self.structure(.deleteColumn) }
        ]
        view.inputAccessoryView = MarkdownEditingToolbar(buttons: formatting + table, done: done)
      } else {
        view.inputAccessoryView = MarkdownEditingToolbar(buttons: [bold, italic], done: done)
      }
    }

    private func button(_ label: String, artwork: MemoraArtwork? = nil, title: String? = nil,
      handler: @escaping () -> Void) -> UIButton {
      var configuration = UIButton.Configuration.plain()
      configuration.title = title
      let iconSize = min(UIFontMetrics(forTextStyle: .body).scaledValue(for: 18), 24)
      configuration.image = artwork?.image(size: iconSize)
      configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
      configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
        var attributes = attributes
        attributes.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
          for: UIFont.systemFont(ofSize: 15, weight: .medium), maximumPointSize: 20)
        return attributes
      }
      configuration.contentInsets = .zero
      let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in handler() })
      button.accessibilityLabel = label
      button.tintColor = .label
      return button
    }

    @objc private func finish() {
      guard let textView else { return }
      // Resigning lets the input method commit its current conversion first.
      textView.resignFirstResponder()
      publishCommittedText(textView)
      parent.isFocused.wrappedValue = false
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
