import SwiftUI

struct OmiPairingView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  var manager: OmiPairingManager
  var isReview = false

  /// Opens the device detail page right after a pairing completes.
  @State private var showsDetails = false

  var body: some View {
    NavigationStack {
      MemoraList {
        Section {
          statusContent
        }

        if (manager.state == .scanning || manager.state == .scanFinished), !manager.devices.isEmpty {
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
            }
          }
        }
      }
      .navigationTitle(isReview ? "Omiを接続（表示例）" : "Omiを接続")
      .navigationBarTitleDisplayMode(.inline)
      .navigationDestination(isPresented: $showsDetails) {
        OmiDeviceDetailView(manager: manager)
      }
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
        }
      }
      .onChange(of: manager.state) { previous, current in
        guard case .connected = current, !isConnected(previous) else { return }
        showsDetails = true
      }
      .onDisappear {
        manager.cancelPairing()
      }
    }
  }

  @ViewBuilder
  private var statusContent: some View {
    switch manager.state {
    case .idle, .remembered:
      VStack(alignment: .leading, spacing: MemoraSpacing.md) {
        Text("Omiの電源を入れて、iPhoneの近くに置きます。")
          .font(.headline)
        Button {
          manager.startScanning()
        } label: {
          Text("Omiを探す")
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: MemoraSpacing.touchTarget, alignment: .center)
        }
        .buttonStyle(.borderedProminent)
      }
      .padding(.vertical, MemoraSpacing.sm)
    case .preparing:
      pairingProgress("Bluetoothを準備しています", cancelTitle: "準備を中止")
    case .scanning:
      pairingProgress("近くのOmiを探しています", cancelTitle: "検索を中止")
    case .scanFinished:
      VStack(alignment: .leading, spacing: MemoraSpacing.md) {
        if manager.devices.isEmpty {
          Text("Omiが見つかりませんでした")
            .font(.headline)
          Text("電源を確認し、iPhoneに近づけてから探してください。")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        } else {
          Text("接続するOmiを選んでください。")
        }
        retryButton
      }
      .padding(.vertical, MemoraSpacing.sm)
    case .connecting(let name):
      pairingProgress("\(name)へ接続しています", cancelTitle: "接続を中止")
    case .connected(let name):
      VStack(alignment: .leading, spacing: MemoraSpacing.md) {
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
      VStack(alignment: .leading, spacing: MemoraSpacing.md) {
        Text("Bluetoothがオフです").font(.headline)
        Text("iPhoneの「設定 › Bluetooth」でオンにしてから、もう一度探してください。")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        retryButton
      }
      .padding(.vertical, MemoraSpacing.sm)
    case .unauthorized:
      VStack(alignment: .leading, spacing: MemoraSpacing.md) {
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
        description: Text("この環境ではOmiを検索できません。書き出した音声は外部レコーダー画面から取り込めます。")
      )
    case .failed(let message):
      VStack(alignment: .leading, spacing: MemoraSpacing.md) {
        Label("接続できませんでした", icon: .exclamationmarkTriangle)
          .font(.headline)
        Text(message)
          .font(.subheadline)
          .foregroundStyle(.secondary)
        retryButton
      }
      .padding(.vertical, MemoraSpacing.sm)
    }
  }

  private var retryButton: some View {
    Button("もう一度探す", icon: .arrowClockwise) { manager.startScanning() }
      .frame(minHeight: MemoraSpacing.touchTarget)
  }

  private func pairingProgress(_ title: String, cancelTitle: String) -> some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.sm) {
      ProgressView(title)
      Button(cancelTitle) { manager.cancelPairing() }
        .frame(minHeight: MemoraSpacing.touchTarget)
    }
    .padding(.vertical, MemoraSpacing.sm)
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
