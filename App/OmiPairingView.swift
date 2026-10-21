import SwiftUI

struct OmiPairingView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  var manager: OmiPairingManager

  /// Opens the device detail page right after a pairing completes.
  @State private var showsDetails = false

  var body: some View {
    NavigationStack {
      MemoraList {
        Section {
          statusContent
        }

        if !manager.devices.isEmpty {
          Section("近くのデバイス") {
            ForEach(manager.devices) { device in
              Button {
                manager.connect(to: device)
              } label: {
                LabeledContent {
                  Text(signalLabel(for: device.signalStrength))
                    .foregroundStyle(.secondary)
                } label: {
                  Label(device.name, icon: .waveform)
                }
              }
              .disabled(isConnecting)
            }
          }
        }
      }
      .navigationTitle("Omiを接続")
      .navigationBarTitleDisplayMode(.inline)
      .navigationDestination(isPresented: $showsDetails) {
        OmiDeviceDetailView(manager: manager)
      }
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("完了", icon: .checkmark) { dismiss() }
        }
      }
      .onChange(of: manager.state) { previous, current in
        guard case .connected = current, !isConnected(previous) else { return }
        showsDetails = true
      }
      .onDisappear {
        manager.stopScanning()
      }
    }
  }

  @ViewBuilder
  private var statusContent: some View {
    switch manager.state {
    case .idle, .remembered:
      VStack(alignment: .leading, spacing: 12) {
        Label("Omiを近くに置いてください", icon: .dotRadiowavesLeftAndRight)
          .font(.headline)
        Text("見つけたデバイスへ、このiPhoneから直接接続します。")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Button("Omiを探す", icon: .antennaRadiowavesLeftAndRight) {
          manager.startScanning()
        }
        .buttonStyle(.borderedProminent)
      }
      .padding(.vertical, MemoraSpacing.sm)
    case .preparing, .scanning:
      HStack(spacing: 12) {
        ProgressView()
        VStack(alignment: .leading, spacing: 3) {
          Text("近くのOmiを探しています")
            .font(.headline)
          Text("電源が入っていることを確認してください。")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.vertical, MemoraSpacing.sm)
    case .connecting(let name):
      HStack(spacing: 12) {
        ProgressView()
        Text("\(name)へ接続しています")
          .font(.headline)
      }
      .padding(.vertical, MemoraSpacing.sm)
    case .connected(let name):
      VStack(alignment: .leading, spacing: 12) {
        Label("\(name)に接続しました", icon: .checkmarkCircleFill)
          .font(.headline)
        Text("次回もこのOmiを接続候補として表示します。")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        NavigationLink {
          OmiDeviceDetailView(manager: manager)
        } label: {
          Label("デバイスの詳細", icon: .infoCircle)
        }
        Button("接続を解除", icon: .xmark) {
          manager.disconnect()
        }
      }
      .padding(.vertical, MemoraSpacing.sm)
    case .bluetoothOff:
      ContentUnavailableView(
        "Bluetoothがオフです",
        icon: .antennaRadiowavesLeftAndRightSlash,
        description: Text("BluetoothをオンにするとOmiを探せます。")
      )
    case .unauthorized:
      VStack(alignment: .leading, spacing: 12) {
        Label("Bluetoothへのアクセスが必要です", icon: .handRaised)
          .font(.headline)
        Text("近くのOmiを見つけて接続するために使用します。")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Button("設定を開く", icon: .gearshape) {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
          }
        }
      }
      .padding(.vertical, MemoraSpacing.sm)
    case .unsupported:
      ContentUnavailableView(
        "iPhone実機で接続できます",
        icon: .iphoneAndArrowForward,
        description: Text("シミュレーターではBluetoothデバイスを検索できません。")
      )
    case .failed(let message):
      VStack(alignment: .leading, spacing: 12) {
        Label("接続できませんでした", icon: .exclamationmarkTriangle)
          .font(.headline)
        Text(message)
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Button("もう一度探す", icon: .arrowClockwise) {
          manager.startScanning()
        }
      }
      .padding(.vertical, MemoraSpacing.sm)
    }
  }

  private var isConnecting: Bool {
    if case .connecting = manager.state { return true }
    return false
  }

  private func isConnected(_ state: OmiPairingManager.ConnectionState) -> Bool {
    if case .connected = state { return true }
    return false
  }

  private func signalLabel(for strength: Int) -> String {
    switch strength {
    case (-55)...:
      "すぐ近く"
    case (-72)..<(-55):
      "近く"
    default:
      "少し離れています"
    }
  }
}
