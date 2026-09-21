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
  /// When set, what is being written is kept under this key, so leaving the
  /// screen or stopping the app does not lose the draft.
  var draftKey: String?
  var onCommit: (String) -> Void

  @Environment(MemoraModel.self) private var model
  @State private var isEditing = false
  @State private var draft = ""
  @State private var editorID = UUID()
  @State private var didRestoreDraft = false
  @State private var draftSaveTask: Task<Void, Never>?
  @FocusState private var isFocused: Bool

  var body: some View {
    Group {
      if isEditing {
        VStack(alignment: .leading, spacing: 8) {
          if didRestoreDraft {
            Label("書きかけの内容を復元しました", systemImage: "arrow.uturn.backward")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }

          MarkdownEditorField(
            markdown: $draft,
            font: font,
            minHeight: minHeight,
            isFocused: $isFocused
          )
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
        .accessibilityAction(named: "編集") { beginEditing() }
      }
    }
    .id(editorID)
    .onChange(of: isFocused) { _, focused in
      if !focused {
        endEditing()
      }
    }
    .onChange(of: draft) { _, newValue in
      scheduleDraftSave(newValue)
    }
    .onDisappear { endEditing() }
  }

  private func beginEditing() {
    guard !isEditing else { return }

    if let draftKey, let stored = DraftStore.load(draftKey), stored != text {
      draft = stored
      didRestoreDraft = true
    } else {
      draft = text
      didRestoreDraft = false
    }

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
    draftSaveTask?.cancel()
    draftSaveTask = nil
    didRestoreDraft = false
    model.inlineEditingCount = max(0, model.inlineEditingCount - 1)
    if model.focusedInlineEditorID == editorID {
      model.focusedInlineEditorID = nil
    }

    if draft != text {
      onCommit(draft)
    }
    // The draft has served its purpose once the text is committed.
    if let draftKey {
      DraftStore.clear(draftKey)
    }
  }

  /// Saves what is being typed a moment after the last keystroke.
  private func scheduleDraftSave(_ value: String) {
    guard isEditing, let draftKey else { return }
    draftSaveTask?.cancel()
    draftSaveTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(800))
      guard !Task.isCancelled else { return }
      DraftStore.save(value, key: draftKey)
    }
  }

  static func attributed(_ markdown: String) -> AttributedString {
    if let cached = markdownCache.value(for: markdown) {
      return cached
    }

    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    let parsed = (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    markdownCache.store(parsed, for: markdown)
    return parsed
  }

  /// Parsing is reused across renders, so scrolling and typing do not re-parse
  /// the same text. `NSCache` is thread safe and evicts on its own.
  private static let markdownCache = MarkdownRenderCache()

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

/// Shows a bulleted list; tapping the section swaps in a one-per-line editor
/// that keeps any formatting on the lines. There is no separate edit button —
/// the content itself is the control.
struct InlineEditableList: View {
  var title: String
  var symbol: String
  var items: [String]
  var emptyText: String
  var onCommit: ([String]) -> Void

  @Environment(MemoraModel.self) private var model
  @State private var isEditing = false
  @State private var draft = ""
  @State private var editorID = UUID()
  @FocusState private var isFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(title, systemImage: symbol)
        .font(.title3.bold())
        .foregroundStyle(.primary)
        .memoraTextReveal()
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { beginEditing() }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("タップして編集")
        .accessibilityAction(named: "編集") { beginEditing() }

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
      } else {
        Group {
          if items.isEmpty {
            Text(emptyText)
              .font(.subheadline)
              .foregroundStyle(.secondary)
          } else {
            VStack(alignment: .leading, spacing: 8) {
              // Index identity: duplicate lines still get their own view.
              ForEach(Array(items.enumerated()), id: \.offset) { _, item in
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
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { beginEditing() }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("タップして編集")
        .accessibilityAction(named: "編集") { beginEditing() }
      }
    }
    .padding(.vertical, 4)
    .id(editorID)
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

/// Remembers the parsed form of recently shown markdown so repeated renders and
/// repeated strings only pay for parsing once.
private final class MarkdownRenderCache {
  private final class Box {
    let value: AttributedString
    init(_ value: AttributedString) { self.value = value }
  }

  private let cache: NSCache<NSString, Box> = {
    let cache = NSCache<NSString, Box>()
    cache.countLimit = 500
    return cache
  }()

  func value(for key: String) -> AttributedString? {
    cache.object(forKey: key as NSString)?.value
  }

  func store(_ value: AttributedString, for key: String) {
    cache.setObject(Box(value), forKey: key as NSString)
  }
}
