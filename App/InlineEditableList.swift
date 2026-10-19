import SwiftUI

/// Shows a bulleted list; tapping it swaps in a one-per-line editor that keeps
/// any formatting on the lines. There is no separate edit button — the content
/// itself is the control. The heading belongs to the enclosing section.
struct InlineEditableList: View {
  var items: [String]
  var emptyText: String
  var onCommit: ([String]) -> Void
  var sourceLabels: [String: String] = [:]
  var onShowSource: ((String) -> Void)? = nil

  @Environment(MemoraModel.self) private var model
  @State private var isEditing = false
  @State private var draft = ""
  @State private var editorID = UUID()
  @FocusState private var isFocused: Bool
  @ScaledMetric(relativeTo: .body) private var readingLineSpacing = MemoraTypography.readingLineSpacing

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if isEditing {
        VStack(alignment: .leading, spacing: 8) {
          MarkdownEditorField(
            markdown: $draft,
            font: .body,
            minHeight: 110,
            isFocused: $isFocused,
            allowsStructure: false
          )

          Text("1行に1つずつ入力します")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      } else {
        if items.isEmpty {
          editingSurface(
            Text(emptyText)
              .font(.subheadline)
              .foregroundStyle(.secondary)
          )
        } else {
          VStack(alignment: .leading, spacing: MarkdownBlockView.blockSpacing) {
            // Index identity: duplicate lines still get their own view.
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
              VStack(alignment: .leading, spacing: 4) {
                editingSurface(
                  HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle().fill(Color.primary).frame(width: 5, height: 5)
                    Text(InlineMarkdownEditor.attributed(item))
                      .font(MemoraTypography.readingBody)
                      .lineSpacing(readingLineSpacing)
                      .frame(maxWidth: .infinity, alignment: .leading)
                  }
                )
                if let onShowSource {
                  Button(sourceLabels[item] ?? "文字起こしを確認", icon: .textBubble) { onShowSource(item) }
                    .font(.subheadline)
                    .frame(minHeight: 44)
                    .accessibilityHint("元の発言で内容を確認します")
                }
              }
            }
          }
        }
      }
    }
    .padding(.vertical, MemoraSpacing.xs)
    .id(editorID)
    .onChange(of: isFocused) { _, focused in
      if !focused {
        endEditing()
      }
    }
    .onDisappear { endEditing() }
  }

  private func editingSurface<Content: View>(_ content: Content) -> some View {
    content.frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .onTapGesture { beginEditing() }
      .accessibilityAddTraits(.isButton)
      .accessibilityHint("タップして編集")
      .accessibilityAction(named: "編集") { beginEditing() }
  }

  private func beginEditing() {
    guard !isEditing else { return }
    draft = items.joined(separator: "\n")
    isEditing = true
    model.inlineEditingCount += 1
    model.focusedInlineEditorID = editorID
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
    if model.focusedInlineEditorID == editorID {
      model.focusedInlineEditorID = nil
    }

    let lines = draft
      .split(separator: "\n")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }

    if lines != items {
      onCommit(lines)
    }
  }
}
