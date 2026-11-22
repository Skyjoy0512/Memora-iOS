import SwiftUI

/// The page reached after pairing: what the connected device is, plus its
/// firmware. Firmware updates are not wired up yet, so the page says so instead
/// of pretending to upgrade.
struct OmiDeviceDetailView: View {
  @Environment(\.dismiss) private var dismiss
  var manager: OmiPairingManager

  @State private var isPairingPresented = false
  @State private var isUnpairingPresented = false

  private var details: OmiPairingManager.DeviceDetails? {
    manager.details
  }

  var body: some View {
    MemoraList {
      Section {
        header
      }

      Section("デバイス") {
        infoRow("名前", details?.name ?? "未取得")
        infoRow("モデル", details?.model ?? "未取得")
        infoRow("メーカー", details?.manufacturer ?? "未取得")
        infoRow("識別子", shortIdentifier)
        infoRow("バッテリー", manager.batteryState.percentage.map { "\($0)%" } ?? "未取得")
      }

      Section {
        infoRow("インストール済み", details?.firmwareVersion ?? "未取得")
      } header: {
        Text("ファームウェア")
      } footer: {
        Text("アプリからの更新は未対応です。")
      }

      Section {
        if !isConnected {
          Button("再接続", icon: .link) { isPairingPresented = true }
        }
        Button("ペアリングを解除", icon: .xmarkCircle, role: .destructive) {
          isUnpairingPresented = true
        }
      }
    }
    .navigationTitle("デバイスの詳細")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $isPairingPresented) { OmiPairingView(manager: manager) }
    .confirmationDialog("ペアリングを解除しますか？", isPresented: $isUnpairingPresented, titleVisibility: .visible) {
      Button("解除", role: .destructive) {
        manager.disconnect()
        dismiss()
      }
    } message: {
      Text("保存した録音は残ります。再び使うときは接続し直してください。")
    }
  }

  private var header: some View {
    HStack(spacing: MemoraSpacing.md) {
      Image(icon: .dotRadiowavesLeftAndRight, size: 22)
        .foregroundStyle(.primary)
        .frame(width: 48, height: 48)
        .background(Color(uiColor: .secondarySystemBackground), in: Circle())

      VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
        Text(deviceName)
          .font(.headline)
        Label(isConnected ? "接続済み" : "未接続", icon: isConnected ? .checkmarkCircleFill : .link)
          .font(.subheadline)
          .foregroundStyle(isConnected ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
      }
    }
    .padding(.vertical, MemoraSpacing.xs)
  }

  private func infoRow(_ title: String, _ value: String) -> some View {
    LabeledContent(title) {
      Text(value)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.trailing)
    }
  }

  private var shortIdentifier: String {
    guard let identifier = details?.identifier.uuidString else { return "未取得" }
    return String(identifier.prefix(8)).uppercased()
  }

  private var isConnected: Bool {
    if case .connected = manager.state { return true }
    return false
  }

  private var deviceName: String {
    if let details { return details.name }
    if case .remembered(let name) = manager.state { return name }
    return "Omi"
  }
}
