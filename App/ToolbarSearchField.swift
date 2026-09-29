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
        Image(icon: .magnifyingglass)
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
      .background(Color(uiColor: .tertiarySystemFill), in: Capsule())

      Button("キャンセル", action: close)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 8)
    .background(Color(uiColor: .systemBackground))
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

extension View {
  /// Shows `ToolbarSearchField` under the navigation bar while `isPresented`.
  /// The screen puts the button that sets it in its own toolbar, so the items
  /// keep the order that screen chose.
  func toolbarSearch(text: Binding<String>, isPresented: Binding<Bool>, prompt: String) -> some View {
    safeAreaInset(edge: .top, spacing: 0) {
      if isPresented.wrappedValue {
        ToolbarSearchField(text: text, isPresented: isPresented, prompt: prompt)
          .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
  }
}
