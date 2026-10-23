import SwiftUI

struct RecorderStatusToolbarButton: View {
  @Environment(MemoraModel.self) private var model

  var body: some View {
    let state = model.omiPairingManager.state
    let isConnected: Bool = if case .connected = state { true } else { false }
    let battery = isConnected ? model.omiPairingManager.batteryState.percentage : nil
    let status: String = switch state {
    case .idle, .remembered: "未接続"
    default: state.shortLabel
    }
    Button {
      model.isRecorderConnectionPresented = true
    } label: {
      HStack(spacing: MemoraSpacing.xs) {
        ToolbarIconGlyph(icon: isConnected ? .dotRadiowavesLeftAndRight : .link)
        Text(battery.map { "\($0)%" } ?? status)
          .font(.caption.weight(.medium))
          .monospacedDigit()
      }
      .frame(minHeight: MemoraIconMetrics.slot)
      .contentShape(Rectangle())
    }
    .accessibilityLabel("デバイスの接続状態")
    .accessibilityValue(battery.map { "\(status)、バッテリー\($0)%" } ?? status)
    .accessibilityHint("外部レコーダーの接続と音声取り込みを開きます")
    .accessibilityIdentifier("recorder.toolbarStatus")
  }
}
