import SwiftUI
import UniformTypeIdentifiers

struct MarketplaceCreationMenu: View {
  var section: ToolsSection?
  @State private var newSkill: MemoraSkill?
  @State private var newTemplate: SummaryMarketTemplate?
  @State private var importingSkill = false
  @State private var importFailure = false

  var body: some View {
    Menu {
      if section == nil || section == .skills {
        Button("スキルを作成", icon: .squareAndPencil) { newSkill = .draft() }
        Button("ファイルから読み込む", icon: .docText) { importingSkill = true }
      }
      if section == nil || section == .templates {
        Button("テンプレートを作成", icon: .docOnDoc) {
          newTemplate = SummaryMarketTemplate(id: "custom.\(UUID().uuidString)",
            title: "", detail: "", symbol: .docText, lead: "", isCustom: true)
        }
      }
      if section == nil || section == .connectors {
        NavigationLink { MCPServersView() } label: { Label("MCPサーバーを追加", icon: .plugsConnected) }
      }
    } label: { ToolbarActionLabel("作成・追加", icon: .plus) }
    .sheet(item: $newSkill) { SkillEditorView(skill: $0) }
    .sheet(item: $newTemplate) { SummaryTemplateEditor(template: $0) }
    .fileImporter(isPresented: $importingSkill, allowedContentTypes: [.plainText, .text], allowsMultipleSelection: false) { result in
      guard case .success(let urls) = result, let url = urls.first else { return }
      let allowed = Set(AgentTool.allCases.map(\.rawValue))
      Task {
        do {
          let text = try await Task.detached(priority: .userInitiated) { try MemoraSkillMarkdown.read(url) }.value
          newSkill = try MemoraSkillMarkdown.parse(text, allowedTools: allowed)
        } catch { importFailure = true }
      }
    }
    .alert("スキルを読み込めません", isPresented: $importFailure) {
      Button("閉じる", role: .cancel) {}
    } message: {
      Text("名前・用途・手順を含むUTF-8のMarkdownを選んでください。最大32KBで、未登録のツールは追加できません。")
    }
  }
}
