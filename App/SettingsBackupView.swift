import SwiftUI
import UniformTypeIdentifiers

/// Exports the records and their media as a versioned package, and restores one
/// when this device has nothing to lose.
struct SettingsBackupView: View {
  @Environment(MemoraModel.self) private var model
  @State private var isExporting = false
  @State private var isImporterPresented = false
  @State private var shareItems: [Any] = []
  @State private var isSharing = false
  @State private var errorMessage: String?
  @State private var statusMessage: String?

  var body: some View {
    List {
      Section {
        LabeledContent("会議", value: "\(model.meetings.count)件")
        LabeledContent("プロジェクト", value: "\(model.spaces.count)件")
        LabeledContent("タスク", value: "\(model.tasks.count)件")
        LabeledContent("ジャーナル", value: "\(model.lifeLogEntries.count)件")
        LabeledContent("人", value: "\(model.people.count)件")
        LabeledContent("AI履歴", value: "\(model.aiHistory.count)件")
        LabeledContent("音声と写真", value: "媒体として同梱")
      } header: {
        Text("含まれるもの")
      } footer: {
        Text("APIキーや設定は含みません。")
      }

      Section {
        Button("バックアップを書き出す", systemImage: "square.and.arrow.up") {
          export()
        }
        .disabled(isExporting)

        Button("バックアップから復元", systemImage: "square.and.arrow.down") {
          isImporterPresented = true
        }
        .disabled(!model.isEmpty)
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
    .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.folder]) { result in
      restore(result)
    }
    .sheet(isPresented: $isSharing) {
      ActivityView(items: shareItems)
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

  private func export() {
    isExporting = true
    do {
      let url = try model.makeBackupPackage(in: FileManager.default.temporaryDirectory)
      shareItems = [url]
      isSharing = true
    } catch {
      errorMessage = "バックアップを書き出せませんでした。ストレージの空き容量を確認してください。"
    }
    isExporting = false
  }

  private func restore(_ result: Result<URL, any Error>) {
    guard case .success(let url) = result else {
      errorMessage = "フォルダを選択できませんでした。"
      return
    }

    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }

    do {
      try model.restoreBackup(from: url)
      statusMessage = "バックアップから復元しました。"
    } catch {
      errorMessage = error.localizedDescription
    }
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
