import SwiftUI

/// The Plaud-style tools hub: what Ask AI can use, what it writes with, and the
/// services it may read. Registration stays in the screens themselves, so a
/// skill, template or connector is created by the same code everywhere.
struct ToolsView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var newSkill: MemoraSkill?
  @State private var newTemplate: SummaryMarketTemplate?

  var body: some View {
    List {
      Section {
        NavigationLink {
          SkillsView()
        } label: {
          SettingsValue(
            title: "マイスキル",
            value: "\(model.skillCatalog.count)個",
            icon: .sparkles
          )
        }

        Button {
          newSkill = MemoraSkill(
            id: "custom-" + UUID().uuidString,
            name: "",
            summary: "",
            instructions: "",
            keywords: [],
            declaredToolNames: []
          )
        } label: {
          SettingsLabel("スキルを作成", icon: .plus)
        }
      } header: {
        Text("スキル")
      } footer: {
        Text("依頼に合う手順をAsk AIが選びます。スキルは外部サービスへの接続や権限を追加しません。")
      }

      Section {
        NavigationLink {
          SummaryTemplateMarketplaceView()
        } label: {
          SettingsValue(
            title: "テンプレート",
            value: "\(model.customTemplates.count)個作成",
            icon: .docText
          )
        }

        Button {
          newTemplate = SummaryMarketTemplate(
            id: "custom.\(UUID().uuidString)",
            title: "",
            detail: "",
            symbol: .docText,
            lead: "",
            isCustom: true
          )
        } label: {
          SettingsLabel("テンプレートを作成", icon: .plus)
        }
      } header: {
        Text("テンプレート")
      } footer: {
        Text("要約の構成を決めます。作成したテンプレートは自動生成の既定にも選べます。")
      }

      Section {
        NavigationLink {
          IntegrationsView()
        } label: {
          SettingsValue(
            title: "コネクタ",
            value: connectorSummary,
            icon: .plugsConnected
          )
        }
      } header: {
        Text("コネクタ")
      } footer: {
        Text("Gmail、カレンダー、Notionなどの外部サービスを接続します。接続は利用者が明示的に行います。")
      }
    }
    .memoraSettingsPage("ツール")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
      }
    }
    .sheet(item: $newSkill) { SkillEditorView(skill: $0) }
    .sheet(item: $newTemplate) { SummaryTemplateEditor(template: $0) }
  }

  private var connectorSummary: String {
    let implemented = IntegrationCatalog.services.filter(\.isImplemented)
    let ready = implemented.filter { model.integrationState($0).isReady }
    guard !implemented.isEmpty else { return "接続先なし" }
    return "\(ready.count)/\(implemented.count)件接続中"
  }
}
