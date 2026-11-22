import SwiftUI

struct ExternalRecorderSettingsView: View {
  @Environment(MemoraModel.self) private var model
  @State private var isOmiPresented = false

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
      } header: {
        Text("Bluetoothで接続")
      }

      Section {
        NavigationLink {
          RecorderAudioImportView(title: "PLAUD", isPlaud: true)
        } label: {
          recorderRow(title: "PLAUD", detail: "アプリから書き出した音声", symbol: .squareAndArrowDown)
        }
        .accessibilityIdentifier("recorder.plaud")

        NavigationLink {
          RecorderAudioImportView(title: "その他・ボイスメモ", isPlaud: false)
        } label: {
          recorderRow(title: "その他・ボイスメモ", detail: "ICレコーダーなどの音声", symbol: .squareAndArrowDown)
        }
        .accessibilityIdentifier("recorder.other")
      } header: {
        Text("書き出した音声を取り込む")
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
  }

  private func recorderRow(title: String, detail: String, symbol: MemoraIcon) -> some View {
    HStack(spacing: MemoraSpacing.md) {
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
