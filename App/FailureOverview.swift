import SwiftUI

struct FailureOverview: View {
  var message: String
  var retry: () -> Void

  var body: some View {
    ContentUnavailableView {
      Label("処理を完了できませんでした", systemImage: "exclamationmark.triangle")
    } description: {
      Text(message)
    } actions: {
      Button("もう一度試す", systemImage: "arrow.clockwise", action: retry)
        .buttonStyle(.borderedProminent)
    }
  }
}

