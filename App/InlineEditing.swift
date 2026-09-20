import Foundation
import SwiftUI

/// Shows markdown text; tapping it swaps in an editor that keeps the text's
/// formatting (bold, italics, links) visible while it is corrected in place.
/// Commits on finishing, so typing does not hit storage.
struct InlineMarkdownEditor: View {
  var text: String
  var placeholder: String
  var font: Font = .body
  var minHeight: CGFloat = 120
  var onCommit: (String) -> Void

  @Environment(MemoraModel.self) private var model
  @State private var isEditing = false
  @State private var draft = ""
  @FocusState private var isFocused: Bool

  var body: some View {
    Group {
      if isEditing {
        VStack(alignment: .leading, spacing: 10) {
          MarkdownEditorField(
            markdown: $draft,
            font: font,
            minHeight: minHeight,
            isFocused: $isFocused
          )

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
    .onDisappear { endEditing() }
  }

  private func beginEditing() {
    guard !isEditing else { return }
    draft = text
    isEditing = true
    model.inlineEditingCount += 1
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(60))
      isFocused = true
    }
  }

  private func endEditing() {
    guard isEditing else { return }
    isEditing = false
    isFocused = false
    model.inlineEditingCount = max(0, model.inlineEditingCount - 1)
    if draft != text {
      onCommit(draft)
    }
  }

  static func attributed(_ markdown: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
  }

  /// Turns the edited attributed text back into markdown so the formatting
  /// survives the round trip through storage and rendering.
  static func markdown(from attributed: AttributedString) -> String {
    var result = ""
    for run in attributed.runs {
      let segment = String(attributed[run.range].characters)
      guard !segment.isEmpty else { continue }

      let intent = run.inlinePresentationIntent ?? []
      var piece = segment

      if intent.contains(.code) {
        piece = "`\(piece)`"
      } else {
        if intent.contains(.strikethrough) { piece = "~~\(piece)~~" }
        if intent.contains(.emphasized) { piece = "*\(piece)*" }
        if intent.contains(.stronglyEmphasized) { piece = "**\(piece)**" }
      }

      if let link = run.link {
        piece = "[\(piece)](\(link.absoluteString))"
      }

      result += piece
    }
    return result
  }
}

/// Shows a bulleted list; an edit button swaps in a one-per-line editor that
/// keeps any formatting on the lines.
struct InlineEditableList: View {
  var title: String
  var symbol: String
  var items: [String]
  var emptyText: String
  var onCommit: ([String]) -> Void

  @Environment(MemoraModel.self) private var model
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
          MarkdownEditorField(
            markdown: $draft,
            font: .body,
            minHeight: 110,
            isFocused: $isFocused
          )

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
    .onDisappear { endEditing() }
  }

  private func beginEditing() {
    guard !isEditing else { return }
    draft = items.joined(separator: "\n")
    isEditing = true
    model.inlineEditingCount += 1
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(60))
      isFocused = true
    }
  }

  private func endEditing() {
    guard isEditing else { return }
    isEditing = false
    isFocused = false
    model.inlineEditingCount = max(0, model.inlineEditingCount - 1)

    let lines = draft
      .split(separator: "\n")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }

    if lines != items {
      onCommit(lines)
    }
  }
}

/// The editing surface itself. On iOS 26 and later it edits an attributed
/// string so bold and the like stay visible; older systems fall back to the
/// markdown source.
private struct MarkdownEditorField: View {
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
