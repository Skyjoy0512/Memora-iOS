import SwiftUI

struct ConversationStatusLine: View {
  var label: String
  var since: Date?
  var isWaiting = false
  var showsShimmer = true

  var body: some View {
    ShimmerText(text: label, isActive: showsShimmer && !isWaiting)
    .font(MemoraTypography.metadata.weight(.medium))
    .padding(.vertical, MemoraSpacing.xs)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(label))
    .accessibilityIdentifier("ai.waitingStatus")
    .task(id: label) { AccessibilityNotification.Announcement(label).post() }
  }
}
