import SwiftUI

/// The page reached after pairing: what the connected device is, plus its
/// firmware. Firmware updates are not wired up yet, so the page says so instead
/// of pretending to upgrade.
struct OmiDeviceDetailView: View {
  @Environment(\.dismiss) private var dismiss
  var manager: OmiPairingManager

  @State private var isFirmwareNoticePresented = false

  private var details: OmiPairingManager.DeviceDetails? {
    manager.details
  }

  var body: some View {
    List {
      Section {
        header
      }

      Section("デバイス") {
        infoRow("名前", details?.name ?? "不明")
        infoRow("モデル", details?.model ?? "取得できませんでした")
        infoRow("メーカー", details?.manufacturer ?? "取得できませんでした")
        infoRow("識別子", shortIdentifier)
      }

      Section {
        infoRow("インストール済み", details?.firmwareVersion ?? "取得できませんでした")
        Button("ファームウェアを更新", systemImage: "arrow.triangle.2.circlepath") {
          isFirmwareNoticePresented = true
        }
      } header: {
        Text("ファームウェア")
      } footer: {
        Text("このアプリはまだファームウェアの更新を行えません。バージョンは接続時にデバイスから読み取った値です。")
      }

      Section {
        Button("接続を解除", systemImage: "xmark.circle", role: .destructive) {
          manager.disconnect()
          dismiss()
        }
      }
    }
    .navigationTitle("デバイスの詳細")
    .navigationBarTitleDisplayMode(.inline)
    .alert("ファームウェア", isPresented: $isFirmwareNoticePresented) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("ファームウェアの確認と更新はまだ対応していません。")
    }
  }

  private var header: some View {
    HStack(spacing: 14) {
      Image(systemName: "dot.radiowaves.left.and.right")
        .font(.title2)
        .foregroundStyle(.tint)
        .frame(width: 48, height: 48)
        .background(Color(uiColor: .secondarySystemBackground), in: Circle())

      VStack(alignment: .leading, spacing: 3) {
        Text(details?.name ?? "Omi")
          .font(.headline)
        Label("接続済み", systemImage: "checkmark.circle.fill")
          .font(.subheadline)
          .foregroundStyle(.green)
      }
    }
    .padding(.vertical, 4)
  }

  private func infoRow(_ title: String, _ value: String) -> some View {
    LabeledContent(title) {
      Text(value)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.trailing)
    }
  }

  private var shortIdentifier: String {
    guard let identifier = details?.identifier.uuidString else { return "不明" }
    return String(identifier.prefix(8)).uppercased()
  }
}
