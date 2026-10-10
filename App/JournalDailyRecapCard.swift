import SwiftUI

struct JournalDailyRecapCard: View {
  var recap: JournalDailyRecap
  var date: Date
  var backdrop: JournalBackdrop
  var onOpenDetails: () -> Void
  @ScaledMetric(relativeTo: .largeTitle) private var daySize = 66.0

  var body: some View {
    Button {
      InteractionFeedback.shared.send(.tap)
      onOpenDetails()
    } label: {
      VStack(alignment: .leading, spacing: 7) {
        Text(Calendar.current.component(.day, from: date).formatted())
          .font(.system(size: daySize, weight: .regular, design: .serif))
        Text(recap.heading)
          .font(.title2.bold())
          .fixedSize(horizontal: false, vertical: true)
        Text(recap.narrative.replacingOccurrences(of: "\n\n", with: " "))
          .font(.subheadline)
          .lineSpacing(4)
          .lineLimit(3)
          .multilineTextAlignment(.leading)
      }
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity, minHeight: 178, alignment: .bottomLeading)
      .padding(20)
      .background { JournalBackdropView(backdrop: backdrop) }
      .clipShape(RoundedRectangle(cornerRadius: 22))
      .contentShape(RoundedRectangle(cornerRadius: 22))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted))。\(recap.heading)。\(recap.narrative)")
    .accessibilityHint("1日のサマリーを開きます")
  }
}
