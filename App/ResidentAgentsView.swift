import SwiftUI

/// Settings › 常駐エージェント: agents that work on their own and post to Ask
/// AI. Offered only on the person's own API key.
struct ResidentAgentsView: View {
  @Environment(MemoraModel.self) private var model
  @State private var editing: ResidentAgent?

  var body: some View {
    let isAvailable = model.residentLLM != nil

    MemoraForm {
      if !isAvailable {
        Section {
          Label("常駐エージェントは、ご自身のAPIキー（BYOK）でクラウドのモデルを使うときだけ動きます。設定の「AI整理」でキーとモデルを登録してください。Memora Intelligenceや端末内のAIでは動きません。", icon: .infoCircle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }

      Section {
        ForEach(model.residentAgents) { agent in
          Button {
            editing = agent
          } label: {
            ResidentAgentRow(agent: agent, isRunning: model.runningResidentIDs.contains(agent.id))
          }
          .buttonStyle(.plain)
          .swipeActions {
            Button("削除", icon: .trash, role: .destructive) {
              model.deleteResident(agent.id)
            }
          }
        }
        Button("エージェントを追加", icon: .plus) {
          editing = ResidentAgent(
            id: UUID(),
            name: "",
            role: "",
            instructions: "",
            symbol: .sparkles,
            trigger: .dailyMorning
          )
        }
      } footer: {
        Text("オンにしたエージェントは、決まった時刻や会議の要約ができたときに記録を読み、結果をAsk AIの会話に投稿します。常駐中は読むだけで、タスクの追加やメールの下書きは「提案」として出し、タップしたときに承認つきで実行します。バックグラウンドで動く時刻はiOSが決めるため、予定より遅れることがあります。その場合は、次にアプリを開いたときに動きます。")
      }
    }
    .navigationTitle("常駐エージェント")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $editing) { agent in
      ResidentAgentEditor(agent: agent)
    }
  }
}

private struct ResidentAgentRow: View {
  var agent: ResidentAgent
  var isRunning: Bool

  var body: some View {
    HStack(spacing: 12) {
      Image(icon: agent.symbol)
        .font(.body)
        .foregroundStyle(agent.isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 3) {
        Text(agent.name.isEmpty ? "名前なし" : agent.name)
          .font(.body.weight(.medium))
          .foregroundStyle(agent.isEnabled ? .primary : .secondary)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if isRunning {
        ProgressView()
      } else if !agent.isEnabled {
        Text("オフ").font(.caption).foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }

  private var subtitle: String {
    var text = agent.trigger.label
    if let last = agent.lastRunAt {
      text += " · 前回 \(last.formatted(date: .abbreviated, time: .shortened))"
    }
    return text
  }
}
