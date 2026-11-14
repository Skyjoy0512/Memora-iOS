import SwiftUI

struct PartialFailureBanner: View {
  var message: String
  var retry: () -> Void

  var body: some View {
    RecordProcessingStateView(title: "文字起こしは使えます", message: message,
      actionTitle: "要約を再試行", action: retry)
  }
}
