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
        .accessibilityIdentifier("recorder.omi")

        Button {
          isPlaudPresented = true
        } label: {
          recorderRow(title: "PLAUD", detail: "音声取り込み", symbol: .waveformBadgeMic)
        }
        .accessibilityIdentifier("recorder.plaud")

        NavigationLink {
          RecorderAudioImportView(title: "他のレコーダー・ボイスメモ", isPlaud: false)
        } label: {
          recorderRow(title: "他のレコーダー・ボイスメモ", detail: "音声取り込み", symbol: .squareAndArrowDown)
        }
        .accessibilityIdentifier("recorder.other")
      } header: {
        Text("レコーダー")
      } footer: {
        Text("OmiはBluetoothで直接接続できます。PLAUD、ICレコーダー、ボイスメモなどは書き出した音声を取り込めます。他社機器のBluetooth直接接続には対応していません。")
      }
    }
    .navigationTitle("外部レコーダー")
    .memoraBackButton()
    .sheet(isPresented: $isOmiPresented) {
      if OmiPairingManager.hasRememberedDevice || model.omiPairingManager.details != nil {
        NavigationStack {
          OmiDeviceDetailView(manager: model.omiPairingManager)
            .toolbar {
              ToolbarItem(placement: .confirmationAction) {
                ToolbarIconButton("完了", icon: .checkmark) { isOmiPresented = false }
              }
            }
        }
      } else {
        OmiPairingView(manager: model.omiPairingManager)
      }
    }
    .sheet(isPresented: $isPlaudPresented) {
      PlaudConnectionView()
    }
  }

  private func recorderRow(title: String, detail: String, symbol: MemoraIcon) -> some View {
    HStack(spacing: 12) {
      MemoraInterfaceIcon(icon: symbol)
      VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
        Text(title).foregroundStyle(.primary)
        Text(detail).font(.footnote).foregroundStyle(.secondary)
      }
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(minHeight: MemoraSpacing.touchTarget)
    .contentShape(Rectangle())
  }
}
