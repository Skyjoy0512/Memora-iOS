import SwiftUI

struct TranscriptSearchControls: View {
  @Environment(MemoraModel.self) private var model
  @Binding var isReadable: Bool
  @Binding var query: String
  @State private var isSearching = false
  @State private var searchFieldID = UUID()
  @FocusState private var isFocused: Bool

  var body: some View {
    VStack(spacing: MemoraSpacing.sm) {
      HStack(spacing: MemoraSpacing.md) {
        TranscriptReadingOptions(isReadable: $isReadable)
        Button("文字起こしを検索", icon: .magnifyingglass) {
          isSearching.toggle()
          if !isSearching { query = ""; isFocused = false }
        }
        .labelStyle(.iconOnly)
        .frame(width: MemoraSpacing.touchTarget, height: MemoraSpacing.touchTarget)
        .accessibilityIdentifier("transcript.search")
      }
      if isSearching {
        HStack {
          TextField("発言・話者を検索", text: $query)
            .focused($isFocused)
            .submitLabel(.search)
            .accessibilityLabel("発言・話者を検索")
            .accessibilityIdentifier("transcript.search.input")
            .id(searchFieldID)
            .task {
              isFocused = true
              model.focusedInlineEditorID = searchFieldID
            }
          Button("検索を閉じる", icon: .xmark) {
            query = ""; isSearching = false; isFocused = false
          }
          .labelStyle(.iconOnly)
          .frame(width: MemoraSpacing.touchTarget, height: MemoraSpacing.touchTarget)
        }
        .padding(.leading, MemoraSpacing.md)
        .background(MemoraPalette.selection, in: Capsule())
      }
    }
    .buttonStyle(.plain)
    .tint(MemoraPalette.textPrimary)
    .onChange(of: isFocused) { _, focused in
      if focused { model.focusedInlineEditorID = searchFieldID }
      else if model.focusedInlineEditorID == searchFieldID { model.focusedInlineEditorID = nil }
    }
    .onDisappear {
      if model.focusedInlineEditorID == searchFieldID { model.focusedInlineEditorID = nil }
    }
  }
}
