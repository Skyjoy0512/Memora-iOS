import SwiftUI
import UniformTypeIdentifiers

struct ExternalRecorderSettingsView: View {
  @Environment(MemoraModel.self) private var model
  @State private var isOmiPresented = false
  @State private var isPlaudPresented = false

  var body: some View {
    MemoraForm {
      Section {
        Button {
          isOmiPresented = true
        } label: {
          recorderRow(
            title: "Omi",
            detail: model.omiPairingManager.state.shortLabel,
            symbol: .dotRadiowavesLeftAndRight
          )
        }

        Button {
          isPlaudPresented = true
        } label: {
          recorderRow(title: "PLAUD", detail: "取り込み可能", symbol: .waveformBadgeMic)
        }
      } header: {
        Text("レコーダー")
      } footer: {
        Text("Bluetoothへのアクセスは、Omiを接続する操作をした時だけ求めます。")
      }
    }
    .navigationTitle("外部レコーダー")
    .memoraBackButton()
    .sheet(isPresented: $isOmiPresented) {
      OmiPairingView(manager: model.omiPairingManager)
    }
    .sheet(isPresented: $isPlaudPresented) {
      PlaudConnectionView()
    }
  }

  private func recorderRow(title: String, detail: String, symbol: MemoraIcon) -> some View {
    HStack(spacing: 12) {
      MemoraIconBadge(symbol: symbol, size: 34)
      Text(title)
        .foregroundStyle(.primary)
      Spacer()
      Text(detail)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Image(icon: .chevronRight)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.primary)
        .accessibilityHidden(true)
    }
    .contentShape(Rectangle())
  }
}
