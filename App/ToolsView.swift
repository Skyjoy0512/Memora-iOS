import SwiftUI
import UniformTypeIdentifiers

struct ToolsView: View {
  @Environment(MemoraModel.self) private var model
  var onOpenSidebar: () -> Void
  @AppStorage("memora.tools.section") private var section = ToolsSection.skills
  @State private var newSkill: MemoraSkill?
  @State private var newTemplate: SummaryMarketTemplate?
  @State private var importingSkill = false
  @State private var importFailure = false
  @State private var query = ""
  @State private var isSearching = false

  var body: some View {
    VStack(spacing: 0) {
      MemoraSectionPicker(items: ToolsSection.allCases, selection: $section) { $0.title }
      .accessibilityLabel("ツールの表示")
      .padding(.horizontal, MemoraSpacing.screen)
      .padding(.top, MemoraSpacing.sm)
      .padding(.bottom, MemoraSpacing.xs)

      Group {
        if isSearching && !CollectionSearch.hasQuery(query) {
          CollectionSearchState(title: "ツールを検索", message: "名前や用途で検索")
            .accessibilityIdentifier("tools.search.prompt")
        } else {
          switch section {
          case .skills: ToolsSkillsList(query: $query)
          case .templates: ToolsTemplatesList(query: $query)
          case .connectors: ToolsConnectorsList(query: $query)
          }
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .listSectionSpacing(MemoraSpacing.lg)
      .environment(\.defaultMinListRowHeight, 72)
      .listRowInsets(EdgeInsets(top: MemoraSpacing.lg, leading: MemoraSpacing.screen,
        bottom: MemoraSpacing.lg, trailing: MemoraSpacing.screen))
    }
    .background(MemoraPalette.background)
    .tint(MemoraPalette.textPrimary)
    .navigationTitle("ツール")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(MemoraPalette.background, for: .navigationBar)
    .toolbarSearch(text: $query, isPresented: $isSearching, prompt: "ツールを検索")
    .toolbar {
      ToolbarActionItem(placement: .topBarLeading) {
        ToolbarIconButton("メニュー", icon: .line3Horizontal) { onOpenSidebar() }
      }
      ToolbarActionItem(usesSystemBackground: true) {
        Menu {
          switch section {
          case .skills:
            Button("スキルを作成", icon: .squareAndPencil) { newSkill = .draft() }
            Button("ファイルから読み込む", icon: .docText) { importingSkill = true }
          case .templates:
            Button("テンプレートを作成", icon: .docOnDoc) {
              newTemplate = SummaryMarketTemplate(id: "custom.\(UUID().uuidString)",
                title: "", detail: "", symbol: .docText, lead: "", isCustom: true)
            }
          case .connectors:
            NavigationLink { MCPServersView() } label: { Label("MCPサーバーを追加", icon: .plugsConnected) }
          }
        } label: { ToolbarActionLabel("ツールを追加", icon: .plus) }
      }
    }
    .onChange(of: model.sidebarSearchRequest) { _, request in
      guard request != nil, model.isToolsPresented else { return }
      isSearching = true
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
