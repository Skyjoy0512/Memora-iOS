import SwiftUI

#if DEBUG
/// Production controls and confirmation, isolated from the person's records.
struct CompanyPresentationReexportExampleView: View {
  @State private var selection = DisplayState.ready
  @State private var confirmsExport = false
  @State private var request: CompanyPresentationExportRequest?
  @State private var notice: LocalizedStringResource?

  var body: some View {
    MemoraForm {
      Section {
        Text("保存や外部送信を行わない架空の表示例です。実際のファイル生成・SQLite保存はホスト検査で確認します。")
          .font(.footnote).foregroundStyle(.secondary)
        Picker("表示する状態", selection: $selection) {
          Text("書き出し前").tag(DisplayState.ready)
          Text("書き出し中").tag(DisplayState.working)
          Text("完了例").tag(DisplayState.finished)
          Text("未対応例").tag(DisplayState.blocked)
        }
      }
      Section {
        CompanyPresentationExportControls(isWorking: selection == .working,
          blockedReason: selection == .blocked ? CompanyPresentationExportError.unsupported.errorDescription : nil,
          templateName: request?.template.name, templateVersion: request?.template.version,
          notice: selection == .finished ? "会社PPTXを書き出しました（表示例）。" : notice,
          start: { confirmsExport = true }, cancel: { selection = .ready; notice = "書き出しを取り消しました（表示例）。" })
      }
      Section {
        DocumentArtifactHistoryView(revisions: Self.revisions,
          preview: { _ in notice = "履歴の表示例です。ファイルは開きません。" },
          share: { _ in notice = "履歴の表示例です。ファイルは共有しません。" })
      } footer: { Text("履歴は架空例です。確認・共有で実際のファイルを開くことはありません。") }
    }
    .navigationTitle("会社PPTXの再出力・表示検証")
    .navigationBarTitleDisplayMode(.inline)
    .modifier(CompanyPresentationExportConfirmation(isPresented: $confirmsExport, request: request) { _ in
      notice = "表示の確認のみです。ファイルは作成していません。"
    })
    .task {
      guard request == nil else { return }
      let source = PPTXWriter.data(for: .init(title: "架空の原本", kind: .slides, slides: [.init(title: "架空の固定ページ", bullets: [])]))
      guard let analysis = try? CompanyTemplateEngine.analyze(source, format: .pptx) else { return }
      var template = CompanyTemplate(name: "架空の会社テンプレート", format: .pptx, fileReference: "fixture.pptx", analysis: analysis)
      template.version = 4
      let document = MemoraDocument(title: "架空の編集後資料", kind: .slides, slides: [PresentationExample.slide(.m03)])
      request = .init(document: document, template: template, workspaceID: nil, generation: UUID())
    }
  }

  private enum DisplayState { case ready, working, finished, blocked }
  private static let revisions = [DocumentArtifactRevision(fileReference: "fictional.pptx", format: .pptx,
    contentRevision: 1, companyTemplateID: UUID(uuidString: "00000000-0000-0000-0000-000000000001"), companyTemplateVersion: 3,
    retainedAt: Date(timeIntervalSince1970: 1_793_145_600))]
}
#endif
