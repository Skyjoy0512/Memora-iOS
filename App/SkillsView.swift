import SwiftUI
import UniformTypeIdentifiers

struct SkillsView: View {
  @Environment(MemoraModel.self) private var model
  @State private var query = ""
  @State private var editing: MemoraSkill?
  @State private var importing = false
  @State private var importFailure = false

  var body: some View {
    let skills = model.skillCatalog.filter {
      query.isEmpty || ([$0.name, $0.summary] + $0.keywords).contains { $0.localizedStandardContains(query) }
    }
    MemoraForm {
      Section {
        ForEach(skills) { skill in
          NavigationLink { SkillDetailView(skillID: skill.id) } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(skill.name)
              Text(skill.summary).font(.caption).foregroundStyle(.secondary)
              Text(model.disabledSkillIDs.contains(skill.id) ? "無効" : "有効").font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, MemoraSpacing.xs)
          }
        }
      } footer: {
        Text("依頼に合う補助手順を自動選択します。スキルは外部サービスへの接続や権限を追加しません。")
      }
    }
    .searchable(text: $query, prompt: "スキルを検索")
    .navigationTitle("スキル").navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Menu {
          Button("手動で作成", icon: .squareAndPencil) {
            editing = MemoraSkill(id: "custom-" + UUID().uuidString, name: "", summary: "", instructions: "", keywords: [], declaredToolNames: [])
          }
          Button("Markdownを読み込む", icon: .docText) { importing = true }
        } label: { ToolbarActionLabel("スキルを追加", icon: .plus) }
      }
    }
    .sheet(item: $editing) { SkillEditorView(skill: $0) }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .text], allowsMultipleSelection: false) { result in
      guard case .success(let urls) = result, let url = urls.first else { return }
      let allowed = Set(AgentTool.allCases.map(\.rawValue))
      Task {
        do {
          let text = try await Task.detached(priority: .userInitiated) { try MemoraSkillMarkdown.read(url) }.value
          editing = try MemoraSkillMarkdown.parse(text, allowedTools: allowed)
        } catch { importFailure = true }
      }
    }
    .alert("スキルを読み込めません", isPresented: $importFailure) { Button("閉じる", role: .cancel) {} } message: {
      Text("UTF-8のMarkdownにname・descriptionを含むメタデータと手順が必要です。最大32KBで、任意のコードや未登録ツールは追加できません。")
    }
  }
}
