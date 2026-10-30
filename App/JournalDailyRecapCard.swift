import SwiftUI

struct JournalDailyRecapCard: View {
  var recap: JournalDailyRecap
  var date: Date
  var backdrop: JournalBackdrop
  var onOpenDetails: () -> Void

  var body: some View {
    Button {
      InteractionFeedback.shared.send(.tap)
      onOpenDetails()
    } label: {
      VStack(alignment: .leading, spacing: 7) {
        HStack {
          Text("1日のサマリー")
            .font(MemoraTypography.metadata.weight(.medium))
          Spacer(minLength: MemoraSpacing.sm)
          Image(icon: .chevronRight, size: MemoraIconMetrics.accessory)
            .accessibilityHidden(true)
        }
        .foregroundStyle(MemoraPalette.textSecondary)
        Text(recap.heading)
          .font(MemoraTypography.sectionHeading)
          .fixedSize(horizontal: false, vertical: true)
        Text(recap.preview.isEmpty ? recap.narrative.replacingOccurrences(of: "\n\n", with: " ") : recap.preview)
          .font(.subheadline)
          .lineSpacing(4)
          .lineLimit(3)
          .multilineTextAlignment(.leading)
        if !recap.context.metrics.isEmpty {
          Text(recap.context.cardMetrics.joined(separator: " · "))
            .font(.caption.weight(.medium))
            .foregroundStyle(MemoraPalette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 5)
        }
      }
      .foregroundStyle(MemoraPalette.textPrimary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(MemoraSpacing.card)
      .memoraCard()
      .contentShape(RoundedRectangle(cornerRadius: MemoraRadius.card))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(date.formatted(Date.FormatStyle(date: .complete, time: .omitted).locale(Locale(identifier: "ja_JP"))))。\(recap.heading)。\(recap.narrative)。\(recap.context.metrics.joined(separator: "、"))")
    .accessibilityHint("1日のサマリーを開きます")
  }
}
