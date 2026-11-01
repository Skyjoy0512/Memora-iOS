import SwiftUI

struct PDFSourcePartitionSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var request: PDFSourcePartitionRequest
  var isPresentedAsSheet = true
  var onSaved: () -> Void = {}
  @State private var job: Task<Void, Never>?
  @State private var failure: String?

  var body: some View {
    if isPresentedAsSheet { NavigationStack { form } }
    else { form }
  }

  private var form: some View {
    MemoraForm {
      Section {
        Text(request.url.lastPathComponent).textSelection(.enabled)
        Text("100ページを目安に、読み返しやすい複数のPDFとして保存します。大きなページがある場合は、さらに小さく分けます。")
          .font(.subheadline).foregroundStyle(.secondary)
      } footer: {
        Text("元のファイルは変更しません。ページ範囲を付けたPDFを追加し、それぞれ要約・検索・Ask AIで使えます。引用のページ番号は分割後のPDF内の番号です。")
      }
      Section {
        Text(request.context.projectID.flatMap { model.space(id: $0)?.name }.map { "保存先：" + $0 } ?? "ライブラリに保存します")
          .font(.subheadline)
      }
      if job != nil { Section { ProgressView("準備しています…") } }
      if let failure { Section { Text(failure).foregroundStyle(MemoraPalette.danger) } }
    }
    .navigationTitle("PDFを分けて追加")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(!isPresentedAsSheet)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        ToolbarIconButton("キャンセル", icon: .xmark) {
          job?.cancel()
          dismiss()
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("追加") { start() }
          .disabled(job != nil || !request.context.isCurrent(in: model))
      }
    }
    .interactiveDismissDisabled(job != nil)
    .onDisappear { job?.cancel() }
    .tint(MemoraPalette.textPrimary)
  }

  private func start() {
    guard job == nil, request.context.isCurrent(in: model) else { return }
    failure = nil
    let originalURL = request.url
    job = Task { @MainActor in
      defer { job = nil }
      do {
        // Native PDFKit work runs away from UI and shares the intake working-set
        // gate with OCR/media. Cancellation reaches the detached worker too.
        let worker = Task.detached(priority: .utility) {
          try await SourceProcessingQueue.shared.perform { try PDFSourcePartition.prepare(originalURL) }
        }
        let partition = try await withTaskCancellationHandler {
          try await worker.value
        } onCancel: { worker.cancel() }
        defer { partition.cleanup() }
        try Task.checkCancellation()
        guard let ids = try await model.importPDFParts(partition, context: request.context), !ids.isEmpty else {
          failure = model.persistenceFailureMessage ?? "保存できませんでした。保存先と空き容量を確認して再試行してください。"
          return
        }
        onSaved()
        if isPresentedAsSheet { dismiss() }
      } catch is CancellationError {
        failure = "追加を停止しました。元のファイルは変更していません。"
      } catch {
        failure = error.localizedDescription
      }
    }
  }
}
