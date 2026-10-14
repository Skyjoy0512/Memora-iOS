import SwiftUI

struct ConversationStatusLine: View {
  var label: String
  var since: Date?
  var isWaiting = false

  var body: some View {
    HStack(spacing: 8) {
      Image(icon: .sparkle).font(.footnote).foregroundStyle(.secondary)
      if isWaiting { Text(label).foregroundStyle(.secondary) }
      else {
        ShimmerText(text: label)
        if let since {
          ElapsedText(since: since).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
        }
      }
    }
    .font(.footnote.weight(.medium))
    .padding(.vertical, 4)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}
