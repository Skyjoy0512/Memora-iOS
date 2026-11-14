import SwiftUI

struct FailureOverview: View {
  var message: String
  var retry: () -> Void
  var showsSummaryDiagnostics = false

  var body: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.sm) {
      RecordProcessingStateView(title: "処理を完了できませんでした", message: message,
        actionTitle: "もう一度試す", action: retry)
      if showsSummaryDiagnostics {
        NavigationLink("原因を確認") { SummaryDiagnosticsView() }
          .font(MemoraTypography.secondary)
          .frame(minHeight: MemoraSpacing.touchTarget)
      }
    }
  }
}
