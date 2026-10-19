import SwiftUI

/// A single selectable text region allows copying across Markdown block boundaries.
/// No rendered links, generated UI descriptions, editing or execution callbacks are exposed.
struct AIAnswerTextSelectionView: View {
  var text: String
  @Environment(\.dismiss) private var dismiss
  @ScaledMetric(relativeTo: .body) private var lineSpacing: CGFloat = 5

  var body: some View {
    NavigationStack {
      ScrollView {
        Text(verbatim: text)
          .font(.body).lineSpacing(lineSpacing).textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading).padding(MemoraSpacing.xl)
      }
      .navigationTitle("テキストを選択")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("完了") { dismiss() }
        }
      }
    }
  }
}
