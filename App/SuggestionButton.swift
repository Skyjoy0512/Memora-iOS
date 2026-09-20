import SwiftUI

struct SuggestionButton: View {
  var title: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack {
        Text(title)
          .foregroundStyle(.primary)
          .multilineTextAlignment(.leading)
        Spacer()
        Image(systemName: "arrow.up.left")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      .contentShape(Rectangle())
      .padding(.vertical, 10)
    }
    .buttonStyle(.plain)
  }
}
