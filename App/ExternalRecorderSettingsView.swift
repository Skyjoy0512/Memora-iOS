import SwiftUI
import UniformTypeIdentifiers

struct ExternalRecorderSettingsView: View {
  @Environment(MemoraModel.self) private var model
  @State private var isOmiPresented = false
  @State private var isPlaudPresented = false

  var body: some View {
    Form {
      Section {
        Button {
          isOmiPresented = true
        } label: {
          recorderRow(
            title: "Omi",
            detail: model.omiPairingManager.state.shortLabel,
            symbol: "dot.radiowaves.left.and.right"
          )
        }

        Button {
          isPlaudPresented = true
        } label: {
          recorderRow(title: "PLAUD", detail: "取り込み可能", symbol: "waveform.badge.mic")
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

  private func recorderRow(title: String, detail: String, symbol: String) -> some View {
    HStack(spacing: 12) {
      MemoraIconBadge(symbol: symbol, size: 34)
      Text(title)
        .foregroundStyle(.primary)
      Spacer()
      Text(detail)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
    }
    .contentShape(Rectangle())
  }
}

private struct OmiPairingView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  var manager: OmiPairingManager

  var body: some View {
    NavigationStack {
      List {
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
                  Label(device.name, systemImage: "waveform")
                }
              }
              .disabled(isConnecting)
            }
          }
        }
      }
      .navigationTitle("Omiを接続")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("完了") { dismiss() }
        }
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
        Label("Omiを近くに置いてください", systemImage: "dot.radiowaves.left.and.right")
          .font(.headline)
        Text("見つけたデバイスへ、このiPhoneから直接接続します。")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Button("Omiを探す", systemImage: "antenna.radiowaves.left.and.right") {
          manager.startScanning()
        }
        .buttonStyle(.borderedProminent)
      }
      .padding(.vertical, 8)
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
      .padding(.vertical, 8)
    case .connecting(let name):
      HStack(spacing: 12) {
        ProgressView()
        Text("\(name)へ接続しています")
          .font(.headline)
      }
      .padding(.vertical, 8)
    case .connected(let name):
      VStack(alignment: .leading, spacing: 12) {
        Label("\(name)に接続しました", systemImage: "checkmark.circle.fill")
          .font(.headline)
        Text("次回もこのOmiを接続候補として表示します。")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Button("接続を解除", systemImage: "xmark") {
          manager.disconnect()
        }
      }
      .padding(.vertical, 8)
    case .bluetoothOff:
      ContentUnavailableView(
        "Bluetoothがオフです",
        systemImage: "antenna.radiowaves.left.and.right.slash",
        description: Text("BluetoothをオンにするとOmiを探せます。")
      )
    case .unauthorized:
      VStack(alignment: .leading, spacing: 12) {
        Label("Bluetoothへのアクセスが必要です", systemImage: "hand.raised")
          .font(.headline)
        Text("近くのOmiを見つけて接続するために使用します。")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Button("設定を開く", systemImage: "gearshape") {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
          }
        }
      }
      .padding(.vertical, 8)
    case .unsupported:
      ContentUnavailableView(
        "iPhone実機で接続できます",
        systemImage: "iphone.and.arrow.forward",
        description: Text("シミュレーターではBluetoothデバイスを検索できません。")
      )
    case .failed(let message):
      VStack(alignment: .leading, spacing: 12) {
        Label("接続できませんでした", systemImage: "exclamationmark.triangle")
          .font(.headline)
        Text(message)
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Button("もう一度探す", systemImage: "arrow.clockwise") {
          manager.startScanning()
        }
      }
      .padding(.vertical, 8)
    }
  }

  private var isConnecting: Bool {
    if case .connecting = manager.state { return true }
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

private struct PlaudConnectionView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var isImporterPresented = false

  var body: some View {
    NavigationStack {
      List {
        Section {
          VStack(alignment: .leading, spacing: 12) {
            Label("PLAUDの記録をMemoraへ", systemImage: "waveform.badge.mic")
              .font(.headline)
            Text("PLAUDアプリから書き出した音声を保存します。文字起こしと要約は、取り込み後に必要なタイミングで開始できます。")
              .font(.subheadline)
              .foregroundStyle(.secondary)
            Button("音声を取り込む", systemImage: "square.and.arrow.down") {
              isImporterPresented = true
            }
            .buttonStyle(.borderedProminent)
          }
          .padding(.vertical, 8)
        }

        Section {
          LabeledContent("Memoraから直接接続", value: "準備中")
        } footer: {
          Text("直接接続にはPLAUD側のアプリ連携設定が必要です。準備が整うまでは音声取り込みを利用できます。")
        }
      }
      .navigationTitle("PLAUDを接続")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("完了") { dismiss() }
        }
      }
      .fileImporter(
        isPresented: $isImporterPresented,
        allowedContentTypes: [.audio],
        allowsMultipleSelection: false
      ) { result in
        guard case .success(let urls) = result, let url = urls.first else { return }
        dismiss()
        Task {
          await model.importAudio(from: url)
        }
      }
    }
  }
}
