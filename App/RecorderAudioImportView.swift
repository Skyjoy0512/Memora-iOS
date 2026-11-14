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
          ? "PLAUDアプリから音声を書き出し、「ファイル」に保存して選択してください。"
          : "PLAUD、ICレコーダー、ボイスメモから音声を書き出し、「ファイル」に保存して選択してください。USBストレージも「ファイル」に表示されていれば選択できます。")
          .foregroundStyle(.secondary)
        Button("音声を選んで取り込む", icon: .squareAndArrowDown) {
          importContext = LocalImportContext(in: model)
          guard importContext != nil else {
            failure = "現在のワークスペースには取り込めません。個人のワークスペースと保存状態を確認してください。"
            showsFailure = true
            return
          }
          importedRecordID = nil
          isImporterPresented = true
        }
        .disabled(isWorking || model.isImporting)
        .accessibilityIdentifier("recorder.importAudio")
        if isWorking { ProgressView("音声を保存しています") }
        if let id = importedRecordID, model.source(id: id) != nil {
          Label("ライブラリに音声を保存しました", icon: .checkmark)
            .accessibilityIdentifier("recorder.importSuccess")
        }
      } footer: {
        Text("再生可能な音声だけを取り込みます。元のファイルは変更しません。対応端末では文字起こしと要約を自動で作成します。外部AIへの送信には既存の許可が必要です。")
      }
      Section {
        LabeledContent("接続方法", value: "音声ファイルの取り込み")
        LabeledContent("Bluetooth直接接続", value: "未対応")
      }
    }
    .navigationTitle(Text(title))
    .navigationBarTitleDisplayMode(.inline)
    .memoraBackButton()
    .interactiveDismissDisabled(isWorking)
    .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.audio]) { result in
      switch result {
      case .success(let url):
        let context = importContext
        isWorking = true
        Task { @MainActor in
          defer { isWorking = false }
          let id = await model.importInformationFile(url, context: context)
          guard let context, context.isCurrent(in: model) else { return }
          if let id {
            importedRecordID = id
          } else {
            failure = model.importErrorMessage ?? model.persistenceFailureMessage ?? "取り込めませんでした。保存先を確認して、もう一度ファイルを選んでください。"
            showsFailure = true
          }
        }
      case .failure(let error):
        guard (error as NSError).code != NSUserCancelledError else { return }
        failure = error.localizedDescription
        showsFailure = true
      }
    }
    .alert("音声を取り込めませんでした", isPresented: $showsFailure) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(failure)
    }
  }
}
