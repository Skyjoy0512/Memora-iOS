import SwiftUI

struct ManualAIProcessingCard: View {
  var symbol: MemoraIcon
  var title: String
  var detail: String
  var actionTitle: String
  var action: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top, spacing: 14) {
        MemoraIconBadge(symbol: symbol, size: 42)
        VStack(alignment: .leading, spacing: 5) {
          Text(title)
            .font(.headline)
          if !detail.isEmpty {
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
          }
        }
      }

      Button(action: action) {
        Label(actionTitle, icon: symbol).frame(maxWidth: .infinity)
      }
      .buttonStyle(MemoraButtonStyle())
    }
    .padding(MemoraSpacing.xl)
    .frame(maxWidth: .infinity, alignment: .leading)
    .memoraCard()
  }
}
