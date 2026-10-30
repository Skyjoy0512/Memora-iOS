import SwiftUI

struct WebResearchView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var mode: WebResearchReport.Mode = .search
  @State private var secondQuery = ""
  @State private var thirdQuery = ""
  @State private var summarizes = true
  @State private var confirms = false
  @State private var failure: String?
  @State private var deletingID: UUID?
  init(initialQuery: String = "", initialMode: WebResearchReport.Mode = .search) {
    _query = State(initialValue: initialQuery)
    _mode = State(initialValue: initialMode)
  }
  var body: some View {
    NavigationStack {
      MemoraForm {
        Section {
          TextField("調べたいこと", text: $query)
          Picker("調査方法", selection: $mode) { ForEach(WebResearchReport.Mode.allCases, id: \.self) { Text($0.label).tag($0) } }
          if mode == .deepResearch {
            TextField("比較する検索語（任意）", text: $secondQuery)
            TextField("別の観点の検索語（任意）", text: $thirdQuery)
          }
          Toggle("AIで比較・要約", isOn: $summarizes)
          Button("調査を開始") { confirms = true }
            .disabled(!KeychainStore.has(WebResearchClient.keyName) || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } footer: {
          Text("検索語はBraveへ送信します。Deep Researchは取得結果の不足に応じて追加検索します。要約には現在のAsk AIモデルを使います。")
        }
        if !KeychainStore.has(WebResearchClient.keyName) {
          Section { Text("設定 › AI整理 › Web検索でAPIキーを登録してください。キー未設定時には検索を実行しません。").foregroundStyle(.secondary) }
        }
        if let failure { Text(failure).foregroundStyle(.secondary) }
        Section("調査履歴") {
          ForEach(model.webResearchReports.filter { $0.workspaceID == model.currentTeamID }) { report in
            NavigationLink { WebResearchDetailView(reportID: report.id, openProjectAction: { id in dismiss(); model.openProject(id) }) } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(report.query).lineLimit(2)
                Text(report.createdAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "ja_JP")))).font(.footnote).foregroundStyle(.secondary)
              }
            }
            .contextMenu {
              Button("調査履歴を削除", role: .destructive) { deletingID = report.id }
                .disabled(model.webResearchBusyIDs.contains(report.id))
            }
          }
        }
      }
      .confirmationDialog("調査履歴を削除しますか？", isPresented: Binding(get: { deletingID != nil }, set: { if !$0 { deletingID = nil } }), titleVisibility: .visible) {
        Button("履歴を削除", role: .destructive) {
          if let id = deletingID, !model.deleteWebResearch(id) { failure = "削除できませんでした。" }
          deletingID = nil
        }
      } message: { Text("プロジェクトへ保存したソースとレポートは残ります。") }
      .navigationTitle("Web検索・調査").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
      .confirmationDialog("外部サービスへ送信しますか？", isPresented: $confirms, titleVisibility: .visible) {
        Button("調査を開始") {
          do {
            let queries = [query, secondQuery, thirdQuery].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard let id = try model.createWebResearch(query: query, mode: mode, queries: queries) else { failure = "調査を保存できませんでした。"; return }
            model.startWebResearch(id, summarize: summarizes)
            query = ""; secondQuery = ""; thirdQuery = ""
          } catch { failure = error.localizedDescription }
        }
        Button("キャンセル", role: .cancel) {}
      } message: {
        Text((mode == .deepResearch ? ResearchPlan.costNotice : "検索APIへ1回、比較AIへ最大1回。契約に応じた料金が発生します。") + "検索語と取得ソースのみを送り、端末の記録や個人メモリは自動で混ぜません。")
      }
    }
  }
}
