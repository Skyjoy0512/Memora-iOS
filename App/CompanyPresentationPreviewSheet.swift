import SwiftUI

struct CompanyPresentationPreviewSheet: View {
  @Environment(\.dismiss) private var dismiss
  var model: MemoraModel
  var request: CompanyPresentationPreviewRequest
  @State private var preview: CompanyPresentationPreview?
  @State private var failure: String?
  @State private var attempt = UUID()
  @State private var pdf: URL?
  @State private var isSharing = false
  @State private var exportID: UUID?

  var body: some View {
    NavigationStack {
      Group {
        if let preview {
          VStack(alignment: .leading, spacing: 0) {
            Text("書式: \(request.template.name) · v\(request.template.version)")
              .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, MemoraSpacing.screen)
            CompanyPresentationPreviewContent(preview: preview)
          }
        }
        else if let failure {
          VStack(alignment: .leading, spacing: MemoraSpacing.md) {
            Text(failure).foregroundStyle(.secondary)
            Button("再試行") { self.failure = nil; attempt = UUID() }
              .frame(minHeight: MemoraSpacing.touchTarget)
          }.padding().frame(maxWidth: .infinity, alignment: .leading)
        } else { ShimmerText(text: "会社書式を確認しています").accessibilityElement(children: .ignore).accessibilityLabel("会社書式を確認しています") }
      }
      .navigationTitle("追加ページ・会社書式")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
        ToolbarItem(placement: .primaryAction) {
          Button("PDF（追加分のみ）") { exportID = UUID() }
            .disabled(preview == nil || exportID != nil || !model.companyPresentationPreviewIsCurrent(request))
        }
      }
      .task(id: attempt) {
        do { preview = try await model.loadCompanyPresentationPreview(request) }
        catch is CancellationError {} catch { failure = error.localizedDescription }
      }
      .task(id: exportID) {
        guard exportID != nil, let preview, model.companyPresentationPreviewIsCurrent(request) else { return }
        let worker = Task.detached(priority: .userInitiated) { try CompanyPresentationPDF.data(for: preview) }
        do {
          let data = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
          try Task.checkCancellation()
          guard model.companyPresentationPreviewIsCurrent(request) else { throw CompanyPresentationPreview.Failure.stale }
          let url = FileManager.default.temporaryDirectory.appendingPathComponent("追加ページ-\(UUID().uuidString).pdf")
          try data.write(to: url, options: .atomic)
          pdf = url; isSharing = true
        } catch is CancellationError {} catch { failure = error.localizedDescription }
        exportID = nil
      }
      .sheet(isPresented: $isSharing, onDismiss: cleanUpPDF) {
        if let pdf { ActivityView(items: [pdf], onComplete: cleanUpPDF) }
      }
      .onChange(of: model.companyPresentationPreviewIsCurrent(request)) { _, current in if !current { dismiss() } }
      .onDisappear { if !isSharing { cleanUpPDF() } }
      .alert("PDFを書き出せませんでした", isPresented: Binding(get: { preview != nil && failure != nil }, set: { if !$0 { failure = nil } })) {
        Button("閉じる", role: .cancel) { failure = nil }
      } message: { Text(failure ?? "") }
    }
  }

  private func cleanUpPDF() {
    if let pdf { try? FileManager.default.removeItem(at: pdf) }
    pdf = nil
  }
}
