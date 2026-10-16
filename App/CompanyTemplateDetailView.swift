import SwiftUI
import QuickLook

struct CompanyTemplateDetailView: View {
  @Environment(MemoraModel.self) private var model
  var template: CompanyTemplate
  @State private var values: [String: String] = [:]
  @State private var output: URL?
  @State private var preview: URL?
  @State private var error: String?
  @State private var busy = false

  var body: some View {
    Form {
      Section {
        Text(template.analysis.notice).font(.footnote)
        LabeledContent("形式", value: template.format.rawValue.uppercased())
        LabeledContent("バージョン", value: String(template.version))
      }
      Section("差し込み内容") {
        ForEach(template.analysis.placeholders, id: \.self) { name in
          TextField(name, text: Binding(get: { values[name] ?? "" }, set: { values[name] = $0 }), axis: .vertical)
        }
        Button("ファイルを生成", icon: .docRichtext) {
          busy = true
          Task {
            defer { busy = false }
            do { output = try await model.generateCompanyDocument(templateID: template.id, title: template.name, values: Dictionary(uniqueKeysWithValues: template.analysis.placeholders.map { ($0, values[$0] ?? "") })) }
            catch { self.error = error.localizedDescription }
          }
        }
        .disabled(!template.analysis.isAvailable || busy)
        if busy { ProgressView("差し込んで検証しています") }
      }
      if let output {
        Section("生成したファイル") {
          Button("プレビュー", icon: .docText) { preview = output }
          ShareLink(item: output) { Label("保存・共有", icon: .squareAndArrowUp) }
          Text("資料に保存済みです。書式は元ファイルのままです。保存前に文字あふれと改ページを確認してください。").font(.footnote).foregroundStyle(.secondary)
        }
      }
      Section("解析した構造") { ForEach(Array(template.analysis.features.enumerated()), id: \.offset) { _, feature in Text(feature).font(.caption).textSelection(.enabled) } }
    }
    .navigationTitle(template.name).navigationBarTitleDisplayMode(.inline)
    .quickLookPreview($preview)

    .alert("生成できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("閉じる", role: .cancel) {} } message: { Text(error ?? "") }
  }
}
