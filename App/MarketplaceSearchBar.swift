import SwiftUI

struct MarketplaceSearchBar: View {
  @Binding var query: String
  @Binding var isSearching: Bool
  var prompt = "マーケットプレイスを検索"
  @FocusState private var isFocused: Bool
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    let layout = typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .trailing, spacing: MemoraSpacing.sm))
      : AnyLayout(HStackLayout(spacing: MemoraSpacing.sm))
    layout {
      HStack(spacing: MemoraSpacing.sm) {
        Image(icon: .magnifyingglass, size: 20)
          .foregroundStyle(MemoraPalette.textSecondary)
          .accessibilityHidden(true)
        TextField(prompt, text: $query)
          .focused($isFocused)
          .submitLabel(.search)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
          .accessibilityLabel(prompt)
          .accessibilityIdentifier("collection.search.input")
          .onSubmit { isFocused = false }
        if !query.isEmpty {
          Button("検索語を消去", icon: .xmark) { query = "" }
            .labelStyle(.iconOnly)
            .frame(width: 44, height: 44)
        }
      }
      .padding(.leading, MemoraSpacing.lg)
      .padding(.trailing, MemoraSpacing.sm)
      .frame(minHeight: 48)
      .memoraGlass(in: Capsule(), interactive: true, backed: false)

      if isSearching {
        Button("キャンセル") {
          isFocused = false
          query = ""
          isSearching = false
        }
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityIdentifier("collection.search.cancel")
      }
    }
    .buttonStyle(.plain)
    .padding(.horizontal, MemoraSpacing.section)
    .padding(.vertical, MemoraSpacing.sm)
    .preservesComposerFocus()
    .onAppear { isFocused = isSearching }
    .onChange(of: isFocused) { _, focused in
      if focused { isSearching = true }
    }
    .onChange(of: isSearching) { _, searching in
      isFocused = searching
    }
  }
}
