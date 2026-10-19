import SwiftUI
import UniformTypeIdentifiers

/// Exports the records and their media as a versioned package, and restores one
/// when this device has nothing to lose.
struct SettingsBackupView: View {
  @Environment(MemoraModel.self) private var model
  @State private var activeWork: BackupWork?
  @State private var isImporterPresented = false
  @State private var shareItems: [Any] = []
  @State private var isSharing = false
  @State private var temporaryBackupURL: URL?
  @State private var errorMessage: String?
  @State private var statusMessage: String?

  private enum BackupWork {
    case exporting
    case restoring

    var label: String {
      switch self {
      case .exporting: "書き出しています…"
      case .restoring: "復元しています…"
      }
    }
  }

  private var isWorking: Bool {
    activeWork != nil
  }

  var body: some View {
    List {
      Section {
        SettingsValue(title: "会議", value: "\(model.meetings.count)件", icon: .docText)
        SettingsValue(title: "プロジェクト", value: "\(model.spaces.count)件", icon: .folder)
        SettingsValue(title: "タスク", value: "\(model.tasks.count)件", icon: .checklist)
        SettingsValue(title: "ジャーナル", value: "\(model.lifeLogEntries.count)件", icon: .calendar)
        SettingsValue(title: "人", value: "\(model.people.count)件", icon: .person2)
        SettingsValue(title: "AI履歴", value: "\(model.aiHistory.count)件", icon: .chatBubble)
        SettingsValue(title: "資料", value: "\(model.documents.count)件", icon: .docText)
        SettingsValue(title: "音声と写真", value: "媒体として同梱", icon: .photo)
      } header: {
        Text("含まれるもの")
      } footer: {
        Text("APIキーや設定、AIメモリ、自作テンプレート、自分の声のサンプルは含みません。")
      }

      Section {
        Button("バックアップを書き出す", icon: .squareAndArrowUp) {
          export()
        }
        .disabled(isWorking)

        Button("バックアップから復元", icon: .squareAndArrowDown) {
          isImporterPresented = true
        }
        .disabled(isWorking || !model.isEmpty)
      } header: {
        Text("バックアップ")
      } footer: {
        Text(model.isEmpty
             ? "復元できるのは、この端末の記録が空のときだけです。"
             : "この端末に記録があるため復元できません。既存の記録を上書きしないためです。")
      }
    }
    .navigationTitle("バックアップ")
    .memoraBackButton()
    .overlay {
      if let activeWork {
        workingOverlay(activeWork.label)
      }
    }
    .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.folder]) { result in
      restore(result)
    }
    .sheet(isPresented: $isSharing, onDismiss: cleanUpTemporaryBackup) {
      ActivityView(items: shareItems, onComplete: cleanUpTemporaryBackup)
    }
    .alert("バックアップ", isPresented: errorPresented) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "")
    }
    .alert("バックアップ", isPresented: statusPresented) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(statusMessage ?? "")
    }
  }

  private func workingOverlay(_ label: String) -> some View {
    VStack(spacing: 12) {
      ProgressView()
      Text(label)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .padding(MemoraSpacing.card)
    .memoraCard()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.ultraThinMaterial)
    .allowsHitTesting(true)
  }

  private func export() {
    guard !isWorking else { return }
    statusMessage = nil
    activeWork = .exporting
    Task {
      defer { activeWork = nil }
      do {
        // The package is written, media and manifest together, before anything
        // says it succeeded. The temp folder is cleaned up after sharing.
        let url = try await model.makeBackupPackage()
        temporaryBackupURL = url
        shareItems = [url]
        isSharing = true
      } catch {
        errorMessage = message(for: error)
      }
    }
  }

  private func restore(_ result: Result<URL, any Error>) {
    guard case .success(let url) = result else {
      // Choosing nothing is not a failure worth an alert.
      if case .failure(let error) = result, isCancellation(error) { return }
      errorMessage = "フォルダを選択できませんでした。"
      return
    }
    guard !isWorking else { return }

    statusMessage = nil
    activeWork = .restoring
    let accessed = url.startAccessingSecurityScopedResource()
    Task {
      defer {
        if accessed { url.stopAccessingSecurityScopedResource() }
        activeWork = nil
      }
      do {
        try await model.restoreBackup(from: url)
        // Only after the media is in place and the records are stored.
        statusMessage = "バックアップから復元しました。"
      } catch {
        errorMessage = message(for: error)
      }
    }
  }

  /// Removes the temporary package once the share sheet is done with it, never
  /// while it is still being shared.
  private func cleanUpTemporaryBackup() {
    guard let url = temporaryBackupURL else { return }
    temporaryBackupURL = nil
    shareItems = []
    try? FileManager.default.removeItem(at: url)
  }

  /// The real reason a backup failed, including a full disk, rather than one
  /// message for every cause.
  private func message(for error: any Error) -> String {
    if let backup = error as? BackupPackage.BackupError,
       let description = backup.errorDescription {
      return description
    }
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteOutOfSpaceError {
      return "ストレージの空き容量が足りません。不要なデータを削除してお試しください。"
    }
    return error.localizedDescription
  }

  private func isCancellation(_ error: any Error) -> Bool {
    let nsError = error as NSError
    return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
  }

  private var errorPresented: Binding<Bool> {
    Binding {
      errorMessage != nil
    } set: { isPresented in
      if !isPresented { errorMessage = nil }
    }
  }

  private var statusPresented: Binding<Bool> {
    Binding {
      statusMessage != nil
    } set: { isPresented in
      if !isPresented { statusMessage = nil }
    }
  }
}
