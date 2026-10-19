import SwiftUI

/// The search field a screen opens from its toolbar's search button. It sits
/// under the navigation bar only while searching, so the list keeps the whole
/// screen the rest of the time.
struct ToolbarSearchField: View {
  @Binding var text: String
  @Binding var isPresented: Bool
  var prompt: String

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @FocusState private var isFocused: Bool

  var body: some View {
    HStack(spacing: 12) {
      HStack(spacing: 6) {
        ArtworkIcon(artwork: .searchIntelligence, size: 20)
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)

        TextField(prompt, text: $text)
          .focused($isFocused)
          .submitLabel(.search)
          .autocorrectionDisabled()

        if !text.isEmpty {
          Button("検索語を消去", icon: .xmarkCircleFill) { text = "" }
            .labelStyle(.iconOnly)
            .foregroundStyle(.tertiary)
            .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 12)
      .frame(minHeight: 40)
      .background(MemoraPalette.selection, in: Capsule())

      Button("キャンセル", action: close)
    }
    .padding(.horizontal, MemoraSpacing.screen)
    .padding(.vertical, 8)
    .background(MemoraPalette.background)
    .onAppear { isFocused = true }
  }

  /// Closing also clears the query, so the screen returns to its full list.
  private func close() {
    isFocused = false
    withAnimation(reduceMotion ? nil : MemoraMotion.control) {
      text = ""
      isPresented = false
    }
  }
}

/// While searching, the field replaces the navigation bar and the model is told,
/// so the tab bar and Ask AI step aside and the search reads as its own screen.
private struct ToolbarSearchModifier: ViewModifier {
  @Environment(MemoraModel.self) private var model
  @Binding var text: String
  @Binding var isPresented: Bool
  var prompt: String

  func body(content: Content) -> some View {
    content
      .toolbar(isPresented ? .hidden : .visible, for: .navigationBar)
      .safeAreaInset(edge: .top, spacing: 0) {
        if isPresented {
          ToolbarSearchField(text: $text, isPresented: $isPresented, prompt: prompt)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
      }
      .onChange(of: isPresented) { _, presented in
        model.isSearchActive = presented
      }
      // Switching tabs clears the flag; the search it belonged to closes too.
      .onChange(of: model.isSearchActive) { _, active in
        guard !active, isPresented else { return }
        text = ""
        isPresented = false
      }
  }
}

extension View {
  /// Shows `ToolbarSearchField` in place of the navigation bar while
  /// `isPresented`. The screen puts the button that sets it in its own toolbar,
  /// so the items keep the order that screen chose.
  func toolbarSearch(text: Binding<String>, isPresented: Binding<Bool>, prompt: String) -> some View {
    modifier(ToolbarSearchModifier(text: text, isPresented: isPresented, prompt: prompt))
  }
}
