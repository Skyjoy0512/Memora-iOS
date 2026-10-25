import SwiftUI

struct FailureOverview: View {
  var message: String
  var retry: () -> Void
  var showsSummaryDiagnostics = false

  var body: some View {
    ContentUnavailableView {
      Label("処理を完了できませんでした", icon: .exclamationmarkTriangle)
    } description: {
      Text(message)
    } actions: {
      Button("もう一度試す", icon: .arrowClockwise, action: retry)
        .buttonStyle(MemoraButtonStyle())
      if showsSummaryDiagnostics {
        NavigationLink("原因を確認") { SummaryDiagnosticsView() }
          .frame(minHeight: 44)
      }
    }
  }
}
