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
        Image(icon: .arrowUpLeft)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.primary)
      }
      .contentShape(Rectangle())
      .padding(.vertical, 10)
    }
    .buttonStyle(.plain)
  }
}
