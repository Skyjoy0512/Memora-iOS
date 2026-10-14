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
          Text("利用できる読み取りツールで確認し、変更は提案として表示します。")
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

        Section {
          DisclosureGroup("実行上限と通知") {
            Stepper("AI呼び出し: \(agent.executionLimits?.modelTurnLimit ?? 8)回", value: Binding(
              get: { agent.executionLimits?.modelTurnLimit ?? 8 },
              set: { var limits = agent.executionLimits ?? ResidentExecutionLimits(); limits.maximumModelTurns = $0; agent.executionLimits = limits }), in: 1...8)
            Stepper("ツール: \(agent.executionLimits?.toolCallLimit ?? 12)回", value: Binding(
              get: { agent.executionLimits?.toolCallLimit ?? 12 },
              set: { var limits = agent.executionLimits ?? ResidentExecutionLimits(); limits.maximumToolCalls = $0; agent.executionLimits = limits }), in: 0...24)
            Toggle("完了を通知", isOn: Binding(get: { agent.executionLimits?.notifies ?? true }, set: {
              var limits = agent.executionLimits ?? ResidentExecutionLimits(); limits.notifies = $0; agent.executionLimits = limits
            }))
            ForEach(AgentTool.residentTools.filter { model.enabledAgentTools.contains($0) }, id: \.self) { tool in
              Toggle(tool.summary, isOn: Binding(
                get: { agent.executionLimits?.allowedToolNames?.contains(tool.rawValue) ?? true },
                set: { enabled in
                  var limits = agent.executionLimits ?? ResidentExecutionLimits()
                  var names = limits.allowedToolNames ?? AgentTool.residentTools.map(\.rawValue)
                  names.removeAll { $0 == tool.rawValue }
                  if enabled { names.append(tool.rawValue) }
                  limits.allowedToolNames = names; agent.executionLimits = limits
                }))
            }
          }
        } footer: {
          Text("上限は1回の実行に適用します。BYOKの料金はモデルと出力により異なります。iOSが実行時刻を決めるため、指定時刻の実行は保証されません。料金未確認のメール取得は自動実行できません。")
        }

        if !isNew {
          Section {
            Button(isRunning ? "停止" : "今すぐ実行", icon: isRunning ? .stopFill : .play) {
              if isRunning { model.cancelResident(agent.id); return }
              Task {
                runResult = nil
                let posted = await model.runResident(agent)
                runResult = posted ? "Ask AIの会話に投稿しました。" : (model.residentRunFailures[agent.id] ?? "実行できませんでした。キーとモデルの設定を確認してください。")
              }
            }
            .disabled(!isRunning && model.residentLLM == nil)
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
    if agent.isEnabled && (agent.executionLimits?.notifies ?? true) {
      Task { _ = await TaskReminderScheduler.requestAuthorization() }
    }
    dismiss()
  }
}
