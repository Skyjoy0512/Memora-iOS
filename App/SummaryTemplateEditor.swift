import SwiftUI

/// Writes or edits one of the person's own templates as a prompt: in their own
/// words, how a summary should be written.
struct SummaryTemplateEditor: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var template: SummaryMarketTemplate
  @FocusState private var isPromptFocused: Bool

  init(template: SummaryMarketTemplate) {
    var template = template
    // A template saved with sections opens as the equivalent prompt.
    if !template.usesPrompt, !template.sections.isEmpty {
      var lines = ["次の見出しでまとめてください: " + template.sections.joined(separator: "、")]
      if !template.focus.isEmpty { lines.append(template.focus) }
      template.prompt = lines.joined(separator: "\n")
    }
    _template = State(initialValue: template)
  }

  private static let symbols: [MemoraIcon] = [
    .docText, .person2, .briefcase, .lightbulb, .checkmarkSeal, .flag, .chartBar, .graduationcap
  ]

  /// Starting points, for a blank page.
  private static let examples: [(title: String, prompt: String)] = [
    ("上司への報告", "上司に報告するメールとして書いてください。結論を最初に3行で、そのあと経緯と次のアクションを箇条書きで。敬語で簡潔に。"),
    ("商談メモ（CRM用）", "CRMに貼る商談メモにしてください。顧客の課題、予算、決裁者、導入時期、競合、温度感（高・中・低）、次のアクションの順に、各1〜2行で。分からない項目は「不明」と書いてください。"),
    ("3行まとめ", "会議の内容を3行だけでまとめてください。1行目は結論、2行目は理由、3行目は次にやること。"),
    ("議事録（社内提出用）", "社内提出用の議事録にしてください。日時・参加者・議題・決定事項・保留事項・次回までの宿題の見出しで、です・ます調で書いてください。")
  ]

  var body: some View {
    NavigationStack {
      MemoraForm {
        Section {
          TextField("名前（例: 上司への報告）", text: $template.title)
          Picker("アイコン", selection: $template.symbol) {
            ForEach(Self.symbols, id: \.self) { symbol in
              Image(icon: symbol).tag(symbol)
            }
          }
          .pickerStyle(.palette)
        }

        Section {
          TextField(
            "例: 営業の上司に報告する形で、顧客の温度感と次のアクションを中心に3行でまとめて",
            text: $template.prompt,
            axis: .vertical
          )
          .lineLimit(6...16)
          .focused($isPromptFocused)

          Menu {
            ForEach(Self.examples, id: \.title) { example in
              Button(example.title) {
                template.prompt = example.prompt
                if template.title.trimmingCharacters(in: .whitespaces).isEmpty {
                  template.title = example.title
                }
              }
            }
          } label: {
            Label("例から始める", icon: .sparkles)
          }
        } header: {
          Text("プロンプト")
        } footer: {
          Text("どんな形で、何を中心に、どのくらいの長さでまとめるかを書きます。AIはこの指示どおりに要約します。文字起こしに無いことは書きません。")
        }

        Section {
          Toggle("アクションアイテム（タスク）を作る", isOn: $template.includesActions)
        } footer: {
          Text("オンにすると、要約の最後に担当と期限つきの行動を付け、タスクに追加します。")
        }
      }
      .navigationTitle(model.customTemplates.contains { $0.id == template.id } ? "テンプレートを編集" : "テンプレートを作成")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存", action: save)
            .disabled(!canSave)
        }
      }
      .onAppear {
        if template.prompt.isEmpty { isPromptFocused = true }
      }
    }
  }

  private var canSave: Bool {
    !template.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && template.usesPrompt
  }

  private func save() {
    template.title = template.title.trimmingCharacters(in: .whitespacesAndNewlines)
    template.prompt = template.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    // The prompt now says how to write it; old sections would only confuse.
    template.sections = []
    template.focus = ""
    template.detail = String(template.prompt.replacingOccurrences(of: "\n", with: " ").prefix(60))
    model.saveCustomTemplate(template)
    dismiss()
  }
}
