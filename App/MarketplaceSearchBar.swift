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
        TextField("", text: $query, prompt: Text(typeSize.isAccessibilitySize ? "検索" : prompt)
          .foregroundStyle(MemoraPalette.textSecondary))
          .focused($isFocused)
          .submitLabel(.search)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
          .accessibilityLabel(prompt)
          .accessibilityIdentifier("collection.search.input")
          .onSubmit { isFocused = false }
        if !query.isEmpty {
          MemoraIconButton("検索語を消去", icon: .xmark) {
            query = ""
            isFocused = true
          }
        }
      }
      .padding(.leading, MemoraSpacing.lg)
      .padding(.trailing, MemoraSpacing.sm)
      .frame(minHeight: 48)
      .memoraGlass(in: Capsule(), interactive: true, backed: false)

      if isSearching {
        Button {
          isFocused = false
          query = ""
          isSearching = false
        } label: {
          Text("キャンセル")
            .frame(minWidth: MemoraSpacing.touchTarget, minHeight: MemoraSpacing.touchTarget)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("collection.search.cancel")
      }
    }
    .buttonStyle(.plain)
    .padding(.horizontal, MemoraSpacing.screen)
    .padding(.vertical, MemoraSpacing.sm)
    .background(MemoraPalette.background, ignoresSafeAreaEdges: .bottom)
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
