import SwiftUI

struct ManualAIProcessingCard: View {
  var symbol: MemoraIcon
  var title: String
  var detail: String
  var actionTitle: String
  var action: () -> Void

  var body: some View {
    RecordProcessingStateView(title: title, message: detail, actionTitle: actionTitle, action: action)
  }
}
