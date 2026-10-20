import SwiftUI
import UniformTypeIdentifiers

struct CompanyTemplatesView: View {
  @Environment(MemoraModel.self) private var model
  @State private var importing = false
  @State private var error: String?
  @State private var busy = false

  var body: some View {
    let templates = model.companyTemplates.filter { $0.workspaceID == model.currentTeamID }
    MemoraForm {
      Section {
        ForEach(templates) { template in
          NavigationLink { CompanyTemplateDetailView(template: template) } label: {
            VStack(alignment: .leading, spacing: 4) {
              Label(template.name, icon: template.format == .docx ? .docRichtext : .rectangleOnRectangleAngled)
              Text(template.format.rawValue.uppercased() + " · " + (template.analysis.isAvailable ? "差し込み可能" : "差し込み未対応"))
                .font(.caption).foregroundStyle(.secondary)
            }
          }
        }
        Button("DOCX・PPTXを登録", icon: .plus) { importing = true }.disabled(busy)
        if busy { ProgressView("端末内で解析しています") }
      } footer: { Text("原本を上書きせず、この端末に別のテンプレートとして保存します。外部サービスへは送信しません。") }
    }
    .tint(.primary)
    .navigationTitle("会社テンプレート").navigationBarTitleDisplayMode(.inline)
    .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "docx")!, UTType(filenameExtension: "pptx")!]) { result in
      if case .success(let url) = result {
        busy = true
        Task { defer { busy = false }; do { try await model.registerCompanyTemplate(url) } catch { self.error = error.localizedDescription } }
      } else if case .failure(let failure) = result { error = failure.localizedDescription }
    }
    .alert("登録できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("閉じる", role: .cancel) {} } message: { Text(error ?? "") }
  }
}
