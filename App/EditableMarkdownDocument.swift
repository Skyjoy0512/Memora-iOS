import SwiftUI

/// A markdown document that is edited where it is read: tapping a heading,
/// paragraph, list item or table value turns just that text into a field in
/// the same style, with the markers left as they are drawn. Return in a list
/// item starts the next one; emptying a block removes it.
struct EditableMarkdownDocument: View {
  var markdown: String
  /// Keeps what is being written, so leaving the screen does not lose it.
  var draftKey: String?
  /// Stores the whole document after one block changes, and reports whether
  /// it was saved.
  var onCommit: (String) async -> Bool
  var onEditSource: (() -> Void)? = nil

  @Environment(MemoraModel.self) private var model
  /// The document as edited here, until the stored copy catches up.
  @State private var working: String?
  @State private var target: EditTarget?
  @State private var draft = ""
  @State private var editorID = UUID()
  @State private var draftSaveTask: Task<Void, Never>?
  @State private var isDraftReady = false
  @State private var draftRevision = UUID()
  @FocusState private var isFocused: Bool
  @ScaledMetric(relativeTo: .body) private var listIndent = MemoraTypography.listIndent

  private enum EditTarget: Hashable {
    case block(Int)
    case cell(block: Int, row: Int, column: Int)

    var blockIndex: Int {
      switch self {
      case .block(let index), .cell(let index, _, _): index
      }
    }

    func shifted(by offset: Int) -> EditTarget {
      switch self {
      case .block(let index): .block(index + offset)
      case .cell(let index, let row, let column): .cell(block: index + offset, row: row, column: column)
      }
    }
  }

  var body: some View {
    let current = working ?? markdown
    let blocks = MarkdownBlockParser.sourcedBlocks(for: current)

    LazyVStack(alignment: .leading, spacing: MarkdownBlockView.blockSpacing) {
      ForEach(blocks.indices, id: \.self) { index in
        row(blocks[index].block, at: index)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .onChange(of: markdown) { _, _ in
      // The stored copy has caught up; it is the one to show again.
      if target == nil, working == markdown { working = nil }
    }
    .onChange(of: isFocused) { _, focused in
      guard !focused else { return }
      // Moving to the next list item passes focus between fields; only a
      // focus that stays away ends editing.
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(150))
        if !isFocused { finish() }
      }
    }
    .onChange(of: draft) { _, newValue in
      draftRevision = UUID()
      handleReturn(in: newValue)
    }
    .onAppear(perform: restoreDraft)
    .onDisappear {
      if target != nil {
        // Let UIKit settle marked text before taking the final draft snapshot.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
      }
      finish()
    }
  }

  // MARK: - Rows

  @ViewBuilder
  private func row(_ block: MarkdownBlock, at index: Int) -> some View {
    if target == .block(index) {
      field(for: block)
        .id(editorID)
    } else if case .table(let header, let rows) = block {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(rows.indices, id: \.self) { rowIndex in
          tableCard(header: header, row: rows[rowIndex], block: index, rowIndex: rowIndex)
        }
      }
    } else {
      MarkdownBlockView(block: block)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { begin(.block(index), text: Self.text(of: block)) }
        .accessibilityAddTraits(isEditable(block) ? .isButton : [])
        .accessibilityHint(isEditable(block) ? "タップして編集" : "")
        .accessibilityAction(named: "編集") { begin(.block(index), text: Self.text(of: block)) }
        .contextMenu {
          Button("コピー", icon: .docOnDoc) { UIPasteboard.general.string = Self.text(of: block) }
          sourceEditingAction()
        }
    }
  }

  /// The field for a block, drawn in the block's own style.
  @ViewBuilder
  private func field(for block: MarkdownBlock) -> some View {
    switch block {
    case .heading(let level, _):
      textField("見出し", font: MarkdownBlockView.headingFont(level))
        .font(MarkdownBlockView.headingFont(level))
        .padding(.top, MarkdownBlockView.headingTopPadding(level))
    case .bullet(let level, let marker, _):
      // Top-aligned: an empty field has no baseline to line the marker up with.
      HStack(alignment: .top, spacing: 8) {
        MarkdownBulletMarker(marker: marker, level: level)
          .font(MarkdownBlockView.bulletFont(level))
          .frame(minWidth: listIndent, alignment: .trailing)
        textField("項目", font: MarkdownBlockView.bulletFont(level))
          .font(MarkdownBlockView.bulletFont(level))
      }
      .padding(.leading, CGFloat(min(level, 4)) * listIndent)
    case .quote:
      HStack(alignment: .top, spacing: MemoraSpacing.md) {
        RoundedRectangle(cornerRadius: 1.5)
          .fill(MemoraPalette.border)
          .frame(width: 3)
        textField("引用", font: MemoraTypography.readingBody)
          .font(MemoraTypography.readingBody)
          .foregroundStyle(.secondary)
      }
      .fixedSize(horizontal: false, vertical: true)
    default:
      textField("本文")
        .font(.body)
    }
  }

  private func textField(_ prompt: String, font: Font = .body) -> some View {
    MarkdownEditorField(markdown: $draft, font: font, minHeight: 44,
      isFocused: $isFocused, onStructure: applyStructure)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// A table row's card, with each value editable on its own.
  private func tableCard(header: [String], row: [String], block: Int, rowIndex: Int) -> some View {
    MarkdownTableRow(header: header, row: row) { column, value, font in
      cell(value, target: .cell(block: block, row: rowIndex, column: column), font: font, header: header, row: row)
        .font(font)
    }
  }

  @ViewBuilder
  private func cell(_ value: String, target cellTarget: EditTarget, font: Font, header: [String], row: [String]) -> some View {
    if target == cellTarget {
      textField("", font: font)
        .id(editorID)
    } else {
      MarkdownBlockView.inline(value.isEmpty ? "入力" : value)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { begin(cellTarget, text: value) }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("タップして編集")
        .contextMenu {
          if case .cell(let block, let rowIndex, _) = cellTarget {
            ForEach(header.indices, id: \.self) { column in
              Button("列\(column + 1)の見出しを編集") {
                begin(.cell(block: block, row: -1, column: column), text: header[column])
              }
            }
            ForEach(header.indices, id: \.self) { column in
              Button("\(header[column])を編集") {
                begin(.cell(block: block, row: rowIndex, column: column),
                  text: row.indices.contains(column) ? row[column] : "")
              }
            }
          }
          sourceEditingAction()
        }
    }
  }

  @ViewBuilder
  private func sourceEditingAction() -> some View {
    // Never attach a SwiftUI context menu above a live UITextView: even an
    // empty parent menu can compete with its native selection gestures.
    if target == nil, let onEditSource {
      Button("Markdownで編集", icon: .chevronLeftForwardslashChevronRight, action: onEditSource)
    }
  }

  // MARK: - Editing

  private func applyStructure(_ action: MarkdownEditingAction) {
    guard let active = target else { return }
    let current = working ?? markdown
    let blocks = MarkdownBlockParser.sourcedBlocks(for: current)
    guard let sourced = blocks[safe: active.blockIndex] else { return }
    let editedBlock = edited(sourced.block, for: active) ?? .paragraph(draft)
    var replacement: MarkdownBlock = editedBlock
    if case .table(let header, var rows) = editedBlock {
      var header = header
      let selectedRow: Int
      let selectedColumn: Int
      if case .cell(_, let row, let column) = active {
        selectedRow = row
        selectedColumn = column
      } else {
        selectedRow = 0
        selectedColumn = 0
      }
      switch action {
      case .addRow: rows.append(Array(repeating: "", count: header.count))
      case .addColumn:
        header.append("見出し")
        rows = rows.map { $0 + [""] }
      case .deleteRow:
        guard rows.count > 1, rows.indices.contains(selectedRow) else { return }
        rows.remove(at: selectedRow)
      case .deleteColumn:
        guard header.count > 1, header.indices.contains(selectedColumn) else { return }
        header.remove(at: selectedColumn)
        rows = rows.map { row in
          var row = row
          if row.indices.contains(selectedColumn) { row.remove(at: selectedColumn) }
          return row
        }
      default: return
      }
      replacement = .table(header: header, rows: rows)
    } else {
      let text = draft
      switch action {
      case .paragraph: replacement = .paragraph("\n" + text + "\n")
      case .heading: replacement = .heading(level: 2, text: text.replacingOccurrences(of: "\n", with: " "))
      case .bullet: replacement = .bullet(level: 0, marker: .dot, text: text)
      case .numbered: replacement = .bullet(level: 0, marker: .number("1"), text: text)
      case .checklist: replacement = .bullet(level: 0, marker: .checkbox(isChecked: false), text: text)
      case .toggleCheck:
        guard case .bullet(let level, .checkbox(let checked), let value) = editedBlock else { return }
        replacement = .bullet(level: level, marker: .checkbox(isChecked: !checked), text: value)
      case .table:
        let updated = MarkdownBlockWriter.replacing(sourced, with: editedBlock, in: current)
        guard let anchor = MarkdownBlockParser.sourcedBlocks(for: updated)[safe: active.blockIndex] else { return }
        let table = MarkdownBlock.table(header: ["項目", "内容"], rows: [["項目1", "内容1"]])
        working = MarkdownBlockWriter.inserting(table, after: anchor, in: updated)
        save(working ?? updated)
        target = .cell(block: active.blockIndex + 1, row: 0, column: 0)
        draft = "項目1"
        refocusEditor()
        return
      default: return
      }
    }
    let updated = MarkdownBlockWriter.replacing(sourced, with: replacement, in: current)
    working = updated
    save(updated)
    if case .table(_, let rows) = replacement {
      target = .cell(block: active.blockIndex, row: 0, column: 0)
      draft = rows.first?.first ?? ""
    } else {
      let refreshed = MarkdownBlockParser.sourcedBlocks(for: updated)
      if let index = refreshed.firstIndex(where: { $0.lines.lowerBound >= sourced.lines.lowerBound }) {
        target = .block(index)
        draft = Self.text(of: refreshed[index].block)
      }
    }
    refocusEditor()
  }

  private func refocusEditor() {
    let intendedTarget = target
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(60))
      guard target == intendedTarget, target != nil else { return }
      isFocused = true
    }
  }

  private func isEditable(_ block: MarkdownBlock) -> Bool {
    if case .rule = block { return false }
    if case .code = block { return false }
    return true
  }

  private static func text(of block: MarkdownBlock) -> String {
    switch block {
    case .heading(_, let text), .paragraph(let text), .bullet(_, _, let text), .quote(let text): text
    case .table, .rule, .code: ""
    }
  }

  private func begin(_ newTarget: EditTarget, text: String) {
    guard isDraftReady else { return }
    draftRevision = UUID()
    if case .block(let index) = newTarget,
       let block = MarkdownBlockParser.sourcedBlocks(for: working ?? markdown)[safe: index]?.block,
       !isEditable(block) {
      return
    }
    var newTarget = newTarget
    if let previous = target {
      // Finishing the previous edit can remove a block (an emptied item) or
      // add lines, which moves the blocks after it.
      let before = MarkdownBlockParser.sourcedBlocks(for: working ?? markdown).count
      finish()
      let shift = MarkdownBlockParser.sourcedBlocks(for: working ?? markdown).count - before
      if shift != 0, previous.blockIndex < newTarget.blockIndex {
        newTarget = newTarget.shifted(by: shift)
      }
    }
    if case .block(let index) = newTarget {
      let block = MarkdownBlockParser.sourcedBlocks(for: working ?? markdown)[safe: index]?.block
      switch block {
      case .heading, .paragraph, .bullet, .quote: break
      default: return
      }
    }
    draft = text
    target = newTarget
    model.inlineEditingCount += 1
    model.focusedInlineEditorID = editorID
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(60))
      isFocused = true
    }
  }

  /// Return ends a one-line block. In a list item it also starts the next
  /// item; in a paragraph it is an ordinary new line.
  private func handleReturn(in value: String) {
    guard let target, value.contains("\n") else {
      scheduleDraftSave()
      return
    }
    let blocks = MarkdownBlockParser.sourcedBlocks(for: working ?? markdown)
    if case .block(let index) = target, case .paragraph = blocks[safe: index]?.block {
      scheduleDraftSave()
      return
    }
    draft = value.replacingOccurrences(of: "\n", with: "")
    if case .block(let index) = target,
       let sourced = blocks[safe: index],
       !draft.trimmingCharacters(in: .whitespaces).isEmpty,
       let next = MarkdownBlockWriter.nextItem(after: sourced.block) {
      commit(continuingWith: next, after: index)
    } else {
      isFocused = false
    }
  }

  /// Writes the block being edited and stops editing.
  private func finish() {
    guard target != nil else { return }
    commit(continuingWith: nil, after: nil)
    target = nil
    isFocused = false
    model.inlineEditingCount = max(0, model.inlineEditingCount - 1)
    if model.focusedInlineEditorID == editorID {
      model.focusedInlineEditorID = nil
    }
  }

  private func commit(continuingWith next: MarkdownBlock?, after index: Int?) {
    guard let target else { return }
    let current = working ?? markdown
    let blocks = MarkdownBlockParser.sourcedBlocks(for: current)
    guard let sourced = blocks[safe: target.blockIndex] else { return }

    var updated = MarkdownBlockWriter.replacing(sourced, with: edited(sourced.block, for: target), in: current)
    if let next, let index {
      let refreshed = MarkdownBlockParser.sourcedBlocks(for: updated)
      if let anchor = refreshed[safe: index] {
        updated = MarkdownBlockWriter.inserting(next, after: anchor, in: updated)
      }
    }

    if next != nil, let index {
      // Straight into the new item, keeping the keyboard up.
      draft = ""
      self.target = .block(index + 1)
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(50))
        isFocused = true
      }
    }
    guard updated != current else { return }
    working = updated
    save(updated)
  }

  /// The block with the edit applied; nil removes a block left empty.
  private func edited(_ block: MarkdownBlock, for target: EditTarget) -> MarkdownBlock? {
    let text = draft.trimmingCharacters(in: .whitespaces)
    switch (block, target) {
    case (.heading(let level, _), .block):
      return text.isEmpty ? nil : .heading(level: level, text: text)
    case (.paragraph, .block):
      let paragraph = draft.trimmingCharacters(in: .whitespacesAndNewlines)
      return paragraph.isEmpty ? nil : .paragraph(paragraph)
    case (.bullet(let level, let marker, _), .block):
      return text.isEmpty ? nil : .bullet(level: level, marker: marker, text: text)
    case (.quote, .block):
      return text.isEmpty ? nil : .quote(text)
    case (.table(var header, var rows), .cell(_, let row, let column)):
      if row == -1 {
        guard header.indices.contains(column) else { return block }
        header[column] = text
        return .table(header: header, rows: rows)
      }
      guard rows.indices.contains(row) else { return block }
      while rows[row].count <= column { rows[row].append("") }
      rows[row][column] = text
      return .table(header: header, rows: rows)
    default:
      return block
    }
  }

  // MARK: - Saving

  private func save(_ document: String) {
    draftSaveTask?.cancel()
    let revision = draftRevision
    if let draftKey {
      try? DraftStore.saveAndWait(document, key: draftKey)
    }
    Task { @MainActor in
      guard await onCommit(document), draftRevision == revision, let draftKey,
            working == document || working == nil else { return }
      DraftStore.clear(draftKey, matching: document)
    }
  }

  /// What is being typed is kept a moment after the last keystroke.
  private func scheduleDraftSave() {
    guard let draftKey, let target else { return }
    let current = working ?? markdown
    draftSaveTask?.cancel()
    draftSaveTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(800))
      guard !Task.isCancelled, self.target == target else { return }
      let blocks = MarkdownBlockParser.sourcedBlocks(for: current)
      guard let sourced = blocks[safe: target.blockIndex] else { return }
      let document = MarkdownBlockWriter.replacing(sourced, with: edited(sourced.block, for: target), in: current)
      DraftStore.save(document, key: draftKey)
    }
  }

  /// A document left mid-edit last time is put back and stored.
  private func restoreDraft() {
    guard !isDraftReady else { return }
    do {
      let stored = try draftKey.flatMap { try DraftStore.readAll([$0])[$0] }
      isDraftReady = true
      if let stored, stored != markdown { working = stored; save(stored) }
    } catch { model.persistenceFailureMessage = error.localizedDescription }
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
