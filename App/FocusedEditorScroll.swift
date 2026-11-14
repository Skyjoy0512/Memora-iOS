import SwiftUI

/// Keeps the inline editor that just took focus above the keyboard. Screens with
/// editable text share this so the timing and motion match everywhere.
private struct FocusedEditorScroller: ViewModifier {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var proxy: ScrollViewProxy

  func body(content: Content) -> some View {
    content
      .onChange(of: model.focusedInlineEditorID) { _, newValue in
        guard let id = newValue else { return }
        Task { @MainActor in
          // Let the keyboard settle before moving, so the target is measured
          // against the final, smaller viewport.
          do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
          guard model.focusedInlineEditorID == id, !Task.isCancelled else { return }
          withAnimation(reduceMotion ? nil : MemoraMotion.screen) {
            proxy.scrollTo(id, anchor: .center)
          }
        }
      }
  }
}

extension View {
  func scrollFocusedEditorAboveKeyboard(in proxy: ScrollViewProxy) -> some View {
    modifier(FocusedEditorScroller(proxy: proxy))
  }
}
