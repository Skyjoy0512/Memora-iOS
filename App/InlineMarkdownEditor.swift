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
  /// Draws headings, lists and tables as a document when the text has them,
  /// as a generated summary does. Off, everything reads as one text.
  var rendersBlocks = false
  /// When set, what is being written is kept under this key, so leaving the
  /// screen or stopping the app does not lose the draft.
  var draftKey: String?
  var allowsStructure = true
  /// Reading-only projection. The edit draft always starts from the source text.
  var displayText: String? = nil
  /// Commits the text and reports whether it was stored. The draft is only
  /// cleared once this says the text is saved, so a failed write keeps what was
  /// being written.
  var onCommit: (String) async -> Bool

  @Environment(MemoraModel.self) private var model
  @State private var isEditing = false
  @State private var draft = ""
  /// The editor can keep input in memory even when the draft store is full.
  @State private var retainedDraft: String?
  @State private var editorID = UUID()
  /// Identifies one editing session, so a commit that finishes late clears only
  /// the draft belonging to the session it was editing.
  @State private var draftSessionID = UUID()
  @State private var didRestoreDraft = false
  @State private var draftSaveTask: Task<Void, Never>?
  @State private var commitTask: Task<Void, Never>?
  @FocusState private var isFocused: Bool
  @ScaledMetric(relativeTo: .body) private var readingLineSpacing = MemoraTypography.readingLineSpacing

  var body: some View {
    Group {
      if isEditing {
        VStack(alignment: .leading, spacing: 8) {
          if didRestoreDraft {
            Label("書きかけの内容を復元しました", icon: .arrowUturnBackward)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }

          MarkdownEditorField(
            markdown: $draft,
            font: font,
            minHeight: minHeight,
            isFocused: $isFocused,
            allowsStructure: allowsStructure
          )
          InlineLinkSummaryView(text: $draft)
        }
      } else if rendersBlocks, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        // A document is edited where it is read, block by block, so it keeps
        // the look it had. The whole source stays reachable for bigger changes.
        EditableMarkdownDocument(markdown: text, draftKey: draftKey,
          onCommit: onCommit, onEditSource: beginEditing)
      } else {
        Group {
          if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(placeholder)
              .foregroundStyle(.tertiary)
          } else {
            Text(Self.attributed(displayText ?? text))
          }
        }
        .font(font)
        .lineSpacing(readingLineSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { beginEditing() }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(displayText == nil ? "タップして編集" : "タップして原文を編集")
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
    .onDisappear {
      if isEditing {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
      }
      endEditing()
    }
  }

  private func beginEditing() {
    guard !isEditing else { return }
    // Reopening supersedes an older save still encoding in the background.
    commitTask?.cancel()
    // A new session under the same key; an older commit must not clear its draft.
    draftSessionID = UUID()

    if let retainedDraft, retainedDraft != text {
      draft = retainedDraft
      didRestoreDraft = true
    } else if let draftKey, let stored = DraftStore.load(draftKey), stored != text {
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

    let value = draft
    let key = draftKey
    let session = draftSessionID
    if value != text {
      retainedDraft = value
      // Keep the latest text in the draft before trying to commit, so a failed
      // or slow write leaves what was just typed rather than an older debounced
      // copy that the end of editing cancelled.
      if let key {
        try? DraftStore.saveAndWait(value, key: key)
      }
      // The draft is only cleared once the record is actually stored, and only
      // if this editing session is still the current one — a newer edit may have
      // written a newer draft under the same key while the commit was in flight.
      commitTask = Task { @MainActor in
        guard await onCommit(value), draftSessionID == session else { return }
        retainedDraft = nil
        if let key { DraftStore.clear(key) }
      }
    } else {
      // Nothing changed, so the safety copy has served its purpose.
      retainedDraft = nil
      if let key { DraftStore.clear(key) }
    }
  }

  /// Saves what is being typed a moment after the last keystroke.
  private func scheduleDraftSave(_ value: String) {
    guard isEditing, let draftKey else { return }
    let session = draftSessionID
    draftSaveTask?.cancel()
    draftSaveTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(800))
      guard !Task.isCancelled, draftSessionID == session, isEditing else { return }
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
