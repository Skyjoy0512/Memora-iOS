import SwiftUI
import UniformTypeIdentifiers

struct ToolsView: View {
  var onOpenSidebar: () -> Void
  @AppStorage("memora.tools.section") private var section = ToolsSection.skills
  @State private var newSkill: MemoraSkill?
  @State private var newTemplate: SummaryMarketTemplate?
  @State private var importingSkill = false
  @State private var importFailure = false

  var body: some View {
    VStack(spacing: 0) {
      Picker("ツールの表示", selection: $section) {
        ForEach(ToolsSection.allCases) { section in Text(section.rawValue).tag(section) }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal, MemoraSpacing.xxl)
      .padding(.top, MemoraSpacing.sm)
      .padding(.bottom, MemoraSpacing.xl)

      Group {
        switch section {
        case .skills: ToolsSkillsList()
        case .templates: ToolsTemplatesList()
        case .connectors: ToolsConnectorsList()
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .listSectionSpacing(MemoraSpacing.section)
      .environment(\.defaultMinListRowHeight, 72)
      .listRowInsets(EdgeInsets(top: MemoraSpacing.lg, leading: MemoraSpacing.xxl,
        bottom: MemoraSpacing.lg, trailing: MemoraSpacing.xxl))
    }
    .background(MemoraPalette.background)
    .tint(MemoraPalette.textPrimary)
    .navigationTitle("ツール")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        ToolbarIconButton("メニュー", icon: .line3Horizontal) { onOpenSidebar() }
      }
      ToolbarItem(placement: .primaryAction) {
        Menu {
          Button("スキルを作成", icon: .squareAndPencil) {
            newSkill = MemoraSkill(id: "custom-" + UUID().uuidString,
              name: "", summary: "", instructions: "", keywords: [], declaredToolNames: [])
          }
          Button("スキルのMarkdownを読み込む", icon: .docText) { importingSkill = true }
          Button("テンプレートを作成", icon: .docOnDoc) {
            newTemplate = SummaryMarketTemplate(id: "custom.\(UUID().uuidString)",
              title: "", detail: "", symbol: .docText, lead: "", isCustom: true)
          }
          NavigationLink { MCPServersView() } label: { Label("MCPサーバーを登録", icon: .plugsConnected) }
        } label: { ToolbarActionLabel("ツールを追加", icon: .plus) }
      }
    }
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
