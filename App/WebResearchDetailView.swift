import SwiftUI

struct WebResearchDetailView: View {
  @Environment(MemoraModel.self) private var model
  var reportID: UUID
  var openProjectAction: ((UUID) -> Void)?
  @Environment(\.dismiss) private var dismiss
  @State private var artifactError: String?
  @State private var creatingArtifact = false
  @State private var isSaving = false
  var body: some View {
    if let report = model.webResearch(id: reportID) {
      List {
        Section {
          Text(report.query).font(.body.weight(.semibold))
          Text(report.mode.label).font(.footnote).foregroundStyle(.secondary)
          if model.webResearchBusyIDs.contains(reportID) {
            ProgressView(report.status == .writing ? "結果をまとめています" : "Webを検索しています")
            Button("停止") { model.cancelWebResearch(reportID) }
          } else if report.status == .searching || report.status == .writing {
            Text("前の調査は中断されています。自動で再送はしません。").foregroundStyle(.secondary)
          }
          if let error = report.error { Text(error).foregroundStyle(.secondary) }
          if let label = report.engineLabel { Text(label + (report.modelLabel.map { " · " + $0 } ?? "")).font(.footnote).foregroundStyle(.secondary) }
          if !report.answer.isEmpty {
            Text(WebResearchContext.linked(report.answer, sent: report.sources.filter { report.sentSourceIDs?.contains($0.id) == true }))
              .textSelection(.enabled).lineSpacing(4)
          }
        }
        if let events = report.progressEvents, !events.isEmpty {
          Section("実行した工程") { ForEach(Array(events.enumerated()), id: \.offset) { _, event in Text(event).font(.footnote) } }
        }
        if let gaps = report.coverageGaps, !gaps.isEmpty {
          Section("根拠の確認事項") { ForEach(gaps, id: \.self) { Text($0).font(.footnote) } }
        }
        Section("検索語") {
          ForEach(report.queries, id: \.self) { query in
            VStack(alignment: .leading, spacing: 4) {
              Text(query)
              Text(report.completedQueries?.contains(query) == true ? "取得済み" : "未完了")
                .font(.footnote).foregroundStyle(.secondary)
            }
          }
        }
        Section("取得ソース（\(report.sources.count)）") {
          ForEach(report.sources) { source in
            DisclosureGroup {
              Text(source.text).font(.subheadline).textSelection(.enabled)
              Link("元のページを開く", destination: source.url).frame(minHeight: 44)
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(source.title).font(.body.weight(.medium)).lineLimit(2)
                Text(source.publishedAt.map { "公開・更新: " + $0.formatted(date: .abbreviated, time: .omitted) } ?? "公開・更新日時は未確認").font(.caption).foregroundStyle(.secondary)
                Text(source.kind.label + (report.citedSourceIDs.contains(source.id) ? " · 回答が引用" :
                  report.sentSourceIDs?.contains(source.id) == true ? " · AIへ送信" : ""))
                  .font(.footnote).foregroundStyle(.secondary)
              }
            }
          }
        }
        if !report.answer.isEmpty && !model.webResearchBusyIDs.contains(reportID) {
          Section {
            Button("Word資料として保存", icon: .docRichtext) {
              creatingArtifact = true
              Task {
                defer { creatingArtifact = false }
                do {
                  let id = try await model.saveResearchDocument(reportID)
                  dismiss(); model.libraryPath.append(.document(id))
                } catch { artifactError = error.localizedDescription }
              }
            }.disabled(creatingArtifact)
          }
        }
        if let projectID = report.savedProjectID {
          Section {
            Text("プロジェクトへ保存済み").foregroundStyle(.secondary)
            if model.space(id: projectID) != nil {
              Button("保存先を開く") {
                if let openProjectAction { openProjectAction(projectID) }
                else { dismiss(); model.openProject(projectID) }
              }
            }
          }
        } else if !report.sources.isEmpty && !model.webResearchBusyIDs.contains(reportID) {
          Section { Button("プロジェクトにまとめる") { isSaving = true } }
        }
      }
      .listStyle(.plain).navigationTitle(report.mode.label).navigationBarTitleDisplayMode(.inline)
      .toolbar(.visible, for: .navigationBar)
      .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
      .alert("資料を保存できませんでした", isPresented: Binding(get: { artifactError != nil }, set: { if !$0 { artifactError = nil } })) { Button("閉じる", role: .cancel) {} } message: { Text(artifactError ?? "") }
      .sheet(isPresented: $isSaving) { WebResearchSaveSheet(reportID: reportID) }
    } else { ContentUnavailableView("調査が見つかりません", icon: .magnifyingglass) }
  }
}
