#if DEBUG
import SwiftUI

struct ProjectSourceOperationCheckView: View {
  @Environment(MemoraModel.self) private var model
  @State private var check = ProjectSourceOperationCheck()
  @State private var selectedSource: ProjectSource?

  var body: some View {
    let sources = model.projectSources.filter { check.sourceIDs.contains($0.id) }
    MemoraList {
      Section {
        Text("モデル・外部APIは使いません。検証用プロジェクトにWord・PowerPoint・Excelを実際に取り込みます。閉じる際に今回の検証データだけを削除します。")
          .font(.footnote).foregroundStyle(.secondary)
        Button("Officeソースの取込を検証") { check.start(in: model) }
          .disabled(check.isRunning || model.currentTeamID != nil || model.isRestoring || model.isStoreProtected)
        Text(check.result).textSelection(.enabled)
      }
      Section("検証ソース") {
        ForEach(sources) { source in
          Button { selectedSource = source } label: { ProjectSourceRow(source: source) }
        }
      }
      Button("検証データを削除", role: .destructive) { check.cleanup(in: model) }
    }
    .tint(MemoraPalette.textPrimary)
    .navigationTitle("ソース取込の検証").navigationBarTitleDisplayMode(.inline)
    .sheet(item: $selectedSource) { source in
      NavigationStack {
        ProjectSourceDetailView(sourceID: source.id)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("閉じる") { selectedSource = nil }
            }
          }
      }
    }
    .onDisappear { if selectedSource == nil { check.cleanup(in: model) } }
  }
}
#endif
