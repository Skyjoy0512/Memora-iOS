import SwiftUI

struct TranscriptSearchControls: View {
  @Binding var isReadable: Bool
  @Binding var query: String
  @State private var isSearching = false
  @FocusState private var isFocused: Bool

  var body: some View {
    VStack(spacing: MemoraSpacing.sm) {
      HStack(spacing: MemoraSpacing.md) {
        TranscriptReadingOptions(isReadable: $isReadable)
        Button("文字起こしを検索", icon: .magnifyingglass) {
          isSearching.toggle()
          isFocused = isSearching
          if !isSearching { query = "" }
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
  }
}
