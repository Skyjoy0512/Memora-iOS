import SwiftUI

/// Points out a weekly review that was written while the person was away, until
/// they open or dismiss it.
struct WeeklyReviewCard: View {
  @Environment(MemoraModel.self) private var model
  var review: MemoraDocument

  var body: some View {
    HStack(spacing: 12) {
      NavigationLink(value: LibraryRoute.document(review.id)) {
        HStack(spacing: 12) {
          MemoraInterfaceIcon(icon: .calendarBadgeCheckmark)

          VStack(alignment: .leading, spacing: 2) {
            Text("振り返りができました")
              .font(.subheadline.weight(.semibold))
            Text(review.displayTitle)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer(minLength: 4)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityHint("週報を開きます")

      Button("閉じる", icon: .xmark) {
        model.markDocumentOpened(review.id)
      }
      .labelStyle(.iconOnly)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .frame(width: 44, height: 44)
      .contentShape(Rectangle())
      .buttonStyle(.plain)
    }
    .padding(MemoraSpacing.md)
    .memoraCard()
  }
}
