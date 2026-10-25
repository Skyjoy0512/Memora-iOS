import SwiftUI

struct SummaryProcessingPicker: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Binding var mode: SummaryProcessingMode
  var supportsControl: Bool

  var body: some View {
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
      : AnyLayout(HStackLayout())
    VStack(alignment: .leading, spacing: 8) {
      layout {
        Text("生成モード")
        if !dynamicTypeSize.isAccessibilitySize { Spacer() }
        Picker("生成モード", selection: $mode) {
          Text("高速").tag(SummaryProcessingMode.fast)
          Text("標準").tag(SummaryProcessingMode.balanced)
          Text("高精度").tag(SummaryProcessingMode.accurate)
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .accessibilityIdentifier("summary.processingMode")
      }
      .frame(minHeight: 44)
      Text(mode.detail)
        .font(.footnote)
        .foregroundStyle(.secondary)
      if mode != .balanced {
        Text(supportsControl
          ? "選んだAIで利用できます。高速の長文処理は、中断時にも同時に実行中の最大2件に料金が発生する可能性があります。"
          : "このAIの推論設定は未検証、または対象外です。モデル・推論設定・同時実行数は変更せず生成します。")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }
}
