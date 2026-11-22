import SwiftUI
import UniformTypeIdentifiers

/// All file-based recorders share the validated SQLite/audio import path.
struct RecorderAudioImportView: View {
  @Environment(MemoraModel.self) private var model
  var title: LocalizedStringResource
  var isPlaud: Bool
  @State private var isImporterPresented = false
  @State private var importContext: LocalImportContext?
  @State private var isWorking = false
  @State private var failure = ""
  @State private var showsFailure = false
  @State private var importedRecordID: UUID?

  var body: some View {
    MemoraForm {
      Section {
        Text(isPlaud
          ? "PLAUDアプリで録音を開き、音声を書き出して「ファイル」に保存します。その音声をここで選びます。"
          : "レコーダーやボイスメモから音声を「ファイル」に保存し、ここで選びます。「ファイル」に表示されるUSBストレージからも選べます。")
          .foregroundStyle(.secondary)
        Button("音声を選んで取り込む", icon: .squareAndArrowDown) {
          importContext = LocalImportContext(in: model)
          guard importContext != nil else {
            failure = "現在のワークスペースには取り込めません。個人のワークスペースと保存状態を確認してください。"
            showsFailure = true
            return
          }
          isImporterPresented = true
        }
        .disabled(isWorking || model.isImporting)
        .accessibilityIdentifier("recorder.importAudio")
        if isWorking { ProgressView("音声を保存しています…") }
        if let id = importedRecordID, model.source(id: id) != nil {
          Label("ライブラリに音声を保存しました", icon: .checkmark)
            .accessibilityIdentifier("recorder.importSuccess")
          NavigationLink {
            ProjectSourceDetailView(sourceID: id)
          } label: {
            Label("取り込んだ音声を開く", icon: .arrowUpRightSquare)
          }
          .accessibilityIdentifier("recorder.openImportedAudio")
          .disabled(isWorking)
        }
      } footer: {
        Text("元のファイルはそのまま残ります。外部AIへの送信には許可が必要です。")
      }
    }
    .navigationTitle(Text(title))
    .navigationBarTitleDisplayMode(.inline)
    .memoraBackButton()
    .interactiveDismissDisabled(isWorking)
    .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.audio]) { result in
      switch result {
      case .success(let url):
        importAudio(url)
      case .failure(let error):
        guard (error as NSError).code != NSUserCancelledError else { return }
        failure = error.localizedDescription
        showsFailure = true
      }
    }
    .alert("音声を取り込めませんでした", isPresented: $showsFailure) {
      Button("閉じる", role: .cancel) {}
    } message: {
      Text(failure)
    }
  }

  private func importAudio(_ url: URL) {
    guard let context = importContext, context.isCurrent(in: model), !isWorking, !model.isImporting else {
      failure = "保存先を確認し、もう一度ファイルを選んでください。"
      showsFailure = true
      return
    }
    isWorking = true
    Task { @MainActor in
      defer { isWorking = false }
      do {
        let ids = try await model.importInformationSources(url, context: context, presentsErrorsLocally: true)
        guard context.isCurrent(in: model) else { return }
        if let id = ids?.first {
          importedRecordID = id
        } else {
          failure = model.persistenceFailureMessage ?? "保存先を確認し、もう一度ファイルを選んでください。"
          showsFailure = true
        }
      } catch {
        guard context.isCurrent(in: model) else { return }
        failure = error.localizedDescription
        showsFailure = true
      }
    }
  }
}
