import SwiftUI

/// Adds or edits one resident agent, and runs it on demand.
struct ResidentAgentEditor: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var agent: ResidentAgent
  @State private var runResult: String?

  init(agent: ResidentAgent) {
    _agent = State(initialValue: agent)
  }

  private var isNew: Bool {
    !model.residentAgents.contains { $0.id == agent.id }
  }

  private var canSave: Bool {
    !agent.name.trimmingCharacters(in: .whitespaces).isEmpty
      && !agent.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    NavigationStack {
      Form {
        let presets = ResidentAgentCatalog.presets.filter { preset in
          !model.residentAgents.contains { $0.id == preset.id }
        }
        if isNew, !presets.isEmpty {
          Section("ひな形から始める") {
            ForEach(presets) { preset in
              Button {
                agent = preset
              } label: {
                Label(preset.name, icon: preset.symbol)
              }
            }
          }
        }

        Section {
          TextField("名前（例: 朝のブリーフ）", text: $agent.name)
          TextField("役割（例: 一日の始まりに要点を伝える）", text: $agent.role, axis: .vertical)
        }

        Section {
          TextField("何を調べて、何を伝えるか", text: $agent.instructions, axis: .vertical)
            .lineLimit(4...10)
        } header: {
          Text("指示")
        } footer: {
          Text("記録・タスク・人物（Gmail連携中はメールも）を読んで作業します。変更は提案として出します。")
        }

        Section {
          Picker("動くとき", selection: $agent.trigger) {
            ForEach(ResidentTrigger.allCases) { trigger in
              Text(trigger.label).tag(trigger)
            }
          }
          Toggle("オン", isOn: $agent.isEnabled)
          Toggle("メモリを参考にする", isOn: $agent.usesMemory)
        }

        if !isNew {
          Section {
            Button(isRunning ? "実行中…" : "今すぐ実行", icon: .play) {
              Task {
                runResult = nil
                let posted = await model.runResident(agent)
                runResult = posted ? "Ask AIの会話に投稿しました。" : "実行できませんでした。キーとモデルの設定を確認してください。"
              }
            }
            .disabled(isRunning || model.residentLLM == nil)
            if let runResult {
              Text(runResult)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
      .navigationTitle(isNew ? "エージェントを追加" : "エージェントを編集")
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
    }
  }

  private var isRunning: Bool {
    model.runningResidentIDs.contains(agent.id)
  }

  private func save() {
    model.updateResident(agent)
    // Asked here, in the foreground, so a background run never has to.
    if agent.isEnabled {
      Task { _ = await TaskReminderScheduler.requestAuthorization() }
    }
    dismiss()
  }
}
