import SwiftUI

struct JournalDailyRecapCard: View {
  var recap: JournalDailyRecap
  var onOpenDetails: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(recap.heading)
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
      Text(recap.narrative)
        .font(.subheadline)
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
      if !recap.highlights.isEmpty {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(Array(recap.highlights.enumerated()), id: \.offset) { _, text in
            Text(text).font(.subheadline).foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      if !recap.isFuture {
        Button("振り返りを見る", action: onOpenDetails)
          .font(.subheadline)
          .frame(minHeight: 44)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .memoraCard(radius: 20)
  }
}
