import SwiftUI

struct ConversationStatusLine: View {
  var label: String
  var since: Date?
  var isWaiting = false
  var showsShimmer = true

  var body: some View {
    HStack(spacing: MemoraSpacing.sm) {
      ShimmerText(text: label, isActive: showsShimmer && !isWaiting)
      if let since { ElapsedText(since: since).monospacedDigit().foregroundStyle(.secondary).accessibilityHidden(true) }
    }
    .font(MemoraTypography.metadata.weight(.medium))
    .padding(.vertical, MemoraSpacing.xs)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(label))
    .accessibilityIdentifier("ai.waitingStatus")
    .task(id: label) { AccessibilityNotification.Announcement(label).post() }
  }
}
