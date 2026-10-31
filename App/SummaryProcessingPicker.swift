import SwiftUI

struct SummaryProcessingPicker: View {
  @Binding var mode: SummaryProcessingMode
  var supportsControl: Bool

  var body: some View {
    if supportsControl {
      Picker("処理方法", selection: $mode) {
        Text("速く").tag(SummaryProcessingMode.fast)
        Text("標準").tag(SummaryProcessingMode.balanced)
        Text("じっくり").tag(SummaryProcessingMode.accurate)
      }
      .accessibilityIdentifier("summary.processingMode")
    } else {
      LabeledContent("処理方法", value: "標準")
    }
  }
}
