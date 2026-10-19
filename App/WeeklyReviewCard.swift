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
          Image(icon: .calendarBadgeCheckmark)
            .font(.title3)
            .foregroundStyle(.tint)
            .frame(width: 40, height: 40)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

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
      .frame(width: 32, height: 32)
      .contentShape(Rectangle())
      .buttonStyle(.plain)
    }
    .padding(12)
    .memoraCard()
  }
}
