import SwiftUI

/// The editing surface itself. On iOS 26 and later it edits an attributed
/// string so bold and the like stay visible; older systems fall back to the
/// markdown source.
struct MarkdownEditorField: View {
  @Binding var markdown: String
  var font: Font
  var minHeight: CGFloat
  var isFocused: FocusState<Bool>.Binding

  var body: some View {
    if #available(iOS 26.0, *) {
      RichMarkdownEditorField(
        markdown: $markdown,
        font: font,
        minHeight: minHeight,
        isFocused: isFocused
      )
    } else {
      TextEditor(text: $markdown)
        .font(font)
        .frame(minHeight: minHeight)
        .scrollContentBackground(.hidden)
        .focused(isFocused)
    }
  }
}

@available(iOS 26.0, *)
private struct RichMarkdownEditorField: View {
  @Binding var markdown: String
  var font: Font
  var minHeight: CGFloat
  var isFocused: FocusState<Bool>.Binding

  @State private var richText = AttributedString()

  var body: some View {
    TextEditor(text: $richText)
      .font(font)
      .frame(minHeight: minHeight)
      .scrollContentBackground(.hidden)
      .focused(isFocused)
      .onAppear { richText = InlineMarkdownEditor.attributed(markdown) }
      .onChange(of: richText) { _, newValue in
        markdown = InlineMarkdownEditor.markdown(from: newValue)
      }
  }
}
