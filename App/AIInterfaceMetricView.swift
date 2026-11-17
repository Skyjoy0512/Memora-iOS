import SwiftUI

struct AIInterfaceMetricView: View {
  var item: NativeAIInterface.Item

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(item.title ?? "").font(.subheadline).foregroundStyle(.secondary)
      Text((item.value ?? 0).formatted()).font(.largeTitle.weight(.semibold)).monospacedDigit()
      if let detail = item.detail, !detail.isEmpty {
        Text(detail).font(.footnote).foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
    .textSelection(.enabled)
  }
}
