import SwiftUI

/// Writes or edits one of the person's own templates: a name, what to pay
/// attention to, and the sections to write under.
struct SummaryTemplateEditor: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var template: SummaryMarketTemplate
  @State private var newSection = ""

  init(template: SummaryMarketTemplate) {
    _template = State(initialValue: template)
  }

  private static let symbols: [MemoraIcon] = [
    .docText, .person2, .briefcase, .lightbulb, .checkmarkSeal, .flag, .chartBar, .graduationcap
  ]

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("名前（例: 週次営業会議）", text: $template.title)
          TextField("説明（任意）", text: $template.detail)
          Picker("アイコン", selection: $template.symbol) {
            ForEach(Self.symbols, id: \.self) { symbol in
              Image(icon: symbol).tag(symbol)
            }
          }
          .pickerStyle(.palette)
        }

        Section {
          TextField("例: 数値と担当者を必ず残す。雑談は省く", text: $template.focus, axis: .vertical)
            .lineLimit(2...5)
        } header: {
          Text("注目すること")
        } footer: {
          Text("AIへの指示として使います。何を重視し、何を省くかを書きます。")
        }

        Section {
          ForEach(template.sections, id: \.self) { section in
            Text(section)
              .swipeActions {
                Button("削除", icon: .trash, role: .destructive) {
                  template.sections.removeAll { $0 == section }
                }
              }
          }
          .onMove { template.sections.move(fromOffsets: $0, toOffset: $1) }

          HStack {
            TextField("見出しを追加", text: $newSection)
              .submitLabel(.done)
              .onSubmit(addSection)
            Button("追加", action: addSection)
              .disabled(newSection.trimmingCharacters(in: .whitespaces).isEmpty)
          }
        } header: {
          Text("見出し")
        } footer: {
          Text("要約はこの順番の見出しで書かれます。長押しで並べ替えられます。")
        }

        Section {
          Toggle("アクションアイテム（タスク）を作る", isOn: $template.includesActions)
        }
      }
      .navigationTitle(model.customTemplates.contains { $0.id == template.id } ? "テンプレートを編集" : "テンプレートを作成")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            addSection()
            template.title = template.title.trimmingCharacters(in: .whitespacesAndNewlines)
            model.saveCustomTemplate(template)
            dismiss()
          }
          .disabled(template.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || template.sections.isEmpty && newSection.isEmpty)
        }
      }
    }
  }

  private func addSection() {
    let trimmed = newSection.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !template.sections.contains(trimmed) else { return }
    template.sections.append(trimmed)
    newSection = ""
  }
}
