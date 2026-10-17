import SwiftUI

struct AgentActivityView: View {
  var steps: [AgentStep]
  var isRunning: Bool
  var isWaiting = false
  var openSource: ((UUID) -> Void)?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isExpanded = false

  var body: some View {
    let summary = AgentActivitySummary(steps: steps, isRunning: isRunning, isWaiting: isWaiting)
    DisclosureGroup(isExpanded: $isExpanded) {
      VStack(alignment: .leading, spacing: 16) {
        if steps.count > 24 { Text("直近24件を表示").font(.caption).foregroundStyle(.secondary) }
        ForEach(steps.suffix(24)) { step in
          VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
              status(step).frame(width: 18)
              Text(step.title).font(.subheadline.weight(.medium))
              Spacer(minLength: 0)
              Text(stateLabel(step)).font(.caption).foregroundStyle(.secondary)
            }
            if let detail = step.detail, !detail.isEmpty {
              Text(detail).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if !step.results.isEmpty || !step.output.isEmpty || step.query != nil {
              DisclosureGroup("取得した情報") {
                VStack(alignment: .leading, spacing: 8) {
                  if let query = step.query { Text("検索語: " + query).font(.caption).foregroundStyle(.secondary) }
                  ForEach(Array(step.results.prefix(20).enumerated()), id: \.offset) { _, result in
                    if let id = result.meetingID, let openSource {
                      Button(result.title, icon: .docText) { openSource(id) }
                        .frame(minHeight: 44).multilineTextAlignment(.leading)
                    } else {
                      Text(result.title).font(.footnote)
                    }
                    if let subtitle = result.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                  }
                  ForEach(Array(step.output.prefix(8).enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                  }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
              }.font(.footnote)
            }
          }
        }
      }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
    } label: {
      Text(summary.label).font(.footnote).foregroundStyle(.secondary).frame(minHeight: 44)
    }
    .tint(.primary)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: isExpanded)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func stateLabel(_ step: AgentStep) -> String {
    switch step.state {
    case .done: "完了"
    case .failed: "失敗"
    case .declined: "実行せず"
    case .running: isRunning ? (isWaiting ? "確認待ち" : "実行中") : "中断"
    }
  }

  @ViewBuilder private func status(_ step: AgentStep) -> some View {
    if step.state == .running && isRunning && !isWaiting && !reduceMotion {
      ProgressView().controlSize(.mini).accessibilityLabel("実行中")
    } else {
      Image(icon: step.state == .done ? .checkmark : step.state == .failed ? .exclamationmarkTriangle : .minusCircle)
        .font(.caption).accessibilityLabel(stateLabel(step))
    }
  }
}
