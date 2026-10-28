import SwiftUI

struct CompanyPresentationPreviewButton: View {
  var model: MemoraModel
  var document: MemoraDocument
  @State private var request: CompanyPresentationPreviewRequest?
  @State private var failure: String?

  var body: some View {
    Button("追加ページを会社書式で確認") {
      do { request = try model.companyPresentationPreviewRequest(for: document) }
      catch { failure = error.localizedDescription }
    }
    .frame(minHeight: MemoraSpacing.touchTarget)
    .accessibilityIdentifier("presentation.companyPreview.open")
    .sheet(item: $request) { CompanyPresentationPreviewSheet(model: model, request: $0) }
    .alert("プレビューできません", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
      Button("閉じる", role: .cancel) { failure = nil }
    } message: { Text(failure ?? "") }
  }
}
