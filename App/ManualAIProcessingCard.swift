import SwiftUI

struct ManualAIProcessingCard: View {
  var symbol: MemoraIcon
  var title: String
  var detail: String
  var actionTitle: String
  var notice = "実行するまでAI利用は発生しません"
  var action: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top, spacing: 14) {
        MemoraIconBadge(symbol: symbol, size: 42)
        VStack(alignment: .leading, spacing: 5) {
          Text(title)
            .font(.headline)
          Text(detail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }

      Label(notice, icon: .handRaised)
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)

      Button(actionTitle, icon: symbol, action: action)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
    }
    .padding(MemoraSpacing.xl)
    .frame(maxWidth: .infinity, alignment: .leading)
    .memoraCard()
  }
}
