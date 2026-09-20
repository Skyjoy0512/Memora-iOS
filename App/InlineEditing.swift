import SwiftUI

/// Shows markdown text; tapping it swaps in a plain editor so it can be
/// corrected in place. Commits on finishing, so typing does not hit storage.
struct InlineMarkdownEditor: View {
  var text: String
  var placeholder: String
  var font: Font = .body
  var minHeight: CGFloat = 120
  var onCommit: (String) -> Void

  @State private var isEditing = false
  @State private var draft = ""
  @FocusState private var isFocused: Bool

  var body: some View {
    Group {
      if isEditing {
        VStack(alignment: .leading, spacing: 10) {
          TextEditor(text: $draft)
            .font(.body)
            .frame(minHeight: minHeight)
            .scrollContentBackground(.hidden)
            .focused($isFocused)

          HStack {
            Spacer()
            Button("完了") { endEditing() }
              .font(.subheadline.weight(.semibold))
          }
        }
      } else {
        Group {
          if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(placeholder)
              .foregroundStyle(.tertiary)
          } else {
            Text(Self.attributed(text))
          }
        }
        .font(font)
        .lineSpacing(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { beginEditing() }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("タップして編集")
      }
    }
    .onChange(of: isFocused) { _, focused in
      if !focused {
        endEditing()
      }
    }
  }

  private func beginEditing() {
    draft = text
    isEditing = true
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(60))
      isFocused = true
    }
  }

  private func endEditing() {
    guard isEditing else { return }
    isEditing = false
    isFocused = false
    if draft != text {
      onCommit(draft)
    }
  }

  static func attributed(_ markdown: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
  }
}

/// Shows a bulleted list; an edit button swaps in a one-per-line editor.
struct InlineEditableList: View {
  var title: String
  var symbol: String
  var items: [String]
  var emptyText: String
  var onCommit: ([String]) -> Void

  @State private var isEditing = false
  @State private var draft = ""
  @FocusState private var isFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label(title, systemImage: symbol)
          .font(.title3.bold())
          .foregroundStyle(.primary)
          .memoraTextReveal()

        Spacer()

        Button(isEditing ? "完了" : "編集") {
          isEditing ? endEditing() : beginEditing()
        }
        .font(.subheadline.weight(.medium))
      }

      if isEditing {
        VStack(alignment: .leading, spacing: 8) {
          TextEditor(text: $draft)
            .font(.body)
            .frame(minHeight: 110)
            .scrollContentBackground(.hidden)
            .focused($isFocused)

          Text("1行に1つずつ入力します")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      } else if items.isEmpty {
        Text(emptyText)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .contentShape(Rectangle())
          .onTapGesture { beginEditing() }
      } else {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(items, id: \.self) { item in
            HStack(alignment: .firstTextBaseline, spacing: 10) {
              Circle()
                .fill(Color.primary)
                .frame(width: 5, height: 5)
              Text(InlineMarkdownEditor.attributed(item))
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }
        .contentShape(Rectangle())
        .onTapGesture { beginEditing() }
      }
    }
    .padding(.vertical, 4)
    .onChange(of: isFocused) { _, focused in
      if !focused {
        endEditing()
      }
    }
  }

  private func beginEditing() {
    draft = items.joined(separator: "\n")
    isEditing = true
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(60))
      isFocused = true
    }
  }

  private func endEditing() {
    guard isEditing else { return }
    isEditing = false
    isFocused = false

    let lines = draft
      .split(separator: "\n")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }

    if lines != items {
      onCommit(lines)
    }
  }
}
