import SwiftUI
import UIKit

struct ShareCaptureView: View {
  var context: NSExtensionContext?
  @State private var projects: [ShareInboxProject] = []
  @State private var selectedID: UUID?
  @State private var isSaving = false
  @State private var failure: String?
  @State private var didSave = false
  var body: some View {
    NavigationStack {
      Form {
        if ShareInboxConfiguration.root == nil {
          Text("Memoraの共有はまだ接続されていません。App Groupsと署名の設定が必要です。")
            .foregroundStyle(.secondary)
        } else if projects.isEmpty {
          Text("Memoraの個人ワークスペースでプロジェクトを作成し、もう一度共有してください。")
            .foregroundStyle(.secondary)
        } else {
          Picker("保存先", selection: $selectedID) {
            ForEach(projects) { Text($0.name).tag(Optional($0.id)) }
          }
          Text("保存後、Memoraを開くとソースへ取り込みます。AIには自動送信しません。")
            .font(.footnote).foregroundStyle(.secondary)
        }
        if let failure { Text(failure).foregroundStyle(.secondary) }
        if isSaving { ProgressView("保存しています") }
        if didSave {
          Text("保存しました。Memoraを開くと取り込みます。")
          Button("完了") { context?.completeRequest(returningItems: nil) }
        }
      }
      .navigationTitle("Memoraに保存").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { context?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)) }
            .disabled(isSaving || didSave)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") { save() }
            .disabled(selectedID == nil || isSaving || didSave)
        }
      }
      .task {
        guard let root = ShareInboxConfiguration.root else { return }
        do {
          projects = try await ShareInboxQueue(root: root).projects()
          selectedID = projects.first?.id
        } catch { failure = error.localizedDescription }
      }
    }
  }

  private func save() {
    guard let id = selectedID, let context, let root = ShareInboxConfiguration.root else { return }
    isSaving = true; failure = nil
    Task { @MainActor in
      defer { isSaving = false }
      let queue = ShareInboxQueue(root: root)
      let requestID = UUID()
      do {
        let folder = try await queue.draft(requestID)
        let items = try await ShareProviderReader.read(context.inputItems, folder: folder)
        try Task.checkCancellation()
        try await queue.publish(ShareInboxRequest(id: requestID, projectID: id, items: items))
        didSave = true
      } catch {
        try? await queue.remove(requestID, draft: true)
        failure = error.localizedDescription
      }
    }
  }
}
