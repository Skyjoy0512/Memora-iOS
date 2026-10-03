import SwiftUI

/// What the AI did on the way to a reply, as an expandable trace: open while it
/// works, settled to one line ("4秒で回答") when done, and tappable to look
/// again. Every row is something that really happened — the search, the
/// records read, each tool — never a made-up reasoning.
struct ThinkingTraceView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var message: AIChatMessage
  /// Set by a tap; until then the trace opens while working and closes after.
  @State private var manualExpanded: Bool?

  private static let dotColors: [Color] = [.accentColor, .orange, .green]

  var body: some View {
    let isWaitingForApproval = model.pendingAgentApproval?.messageID == message.id
    let working = message.isThinking && !isWaitingForApproval
    let expanded = manualExpanded ?? (message.isThinking || isWaitingForApproval)

    VStack(alignment: .leading, spacing: 4) {
      Button {
        withAnimation(reduceMotion ? nil : MemoraMotion.screen) {
          manualExpanded = !expanded
        }
      } label: {
        HStack(spacing: 8) {
          Image(icon: .sparkles)
            .font(.footnote)
            .foregroundStyle(working ? .secondary : .tertiary)
          Group {
            if working {
              ShimmerText(text: activeLabel)
            } else {
              Text(isWaitingForApproval ? "確認を待っています" : doneLabel)
                .foregroundStyle(.secondary)
                .transition(.opacity)
            }
          }
          .font(.footnote.weight(.medium))
          Image(icon: .chevronDown)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(expanded ? 180 : 0))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(working ? activeLabel : doneLabel)
      .accessibilityValue(expanded ? "開いています" : "閉じています")
      .accessibilityHint("タップで経過を\(expanded ? "閉じます" : "開きます")")

      if expanded {
        trace
          .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .animation(reduceMotion ? nil : MemoraMotion.screen, value: expanded)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: message.agentSteps)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: message.sources.count)
  }

  // MARK: - Labels

  private var activeLabel: String {
    message.isAgentReply ? "作業しています" : "考えています"
  }

  private var doneLabel: String {
    let seconds = message.elapsedSeconds.map { "\($0)秒" }
    if message.isAgentReply {
      let count = message.agentSteps.filter { $0.state == .done }.count
      return [count > 0 ? "\(count)個の作業" : nil, seconds].compactMap { $0 }.joined(separator: "・")
    }
    let read = message.sources.isEmpty ? nil : "\(message.sources.count)件の記録を参照"
    return [seconds.map { "\($0)で回答" }, read].compactMap { $0 }.joined(separator: "・")
  }

  // MARK: - Trace

  private var trace: some View {
    VStack(alignment: .leading, spacing: 2) {
      if let query = message.traceQuery {
        HStack(spacing: 8) {
          Image(icon: .magnifyingglass)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(width: 14)
          Text(query)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .frame(minHeight: 24)
        .transition(.opacity.combined(with: .offset(y: 6)))
      }

      ForEach(Array(message.agentSteps.enumerated()), id: \.element.id) { index, step in
        stepRow(step)
        // In an answer, the records read follow the search that found them.
        if !message.isAgentReply, index == 0 {
          ForEach(Array(message.sources.enumerated()), id: \.element.id) { sourceIndex, source in
            sourceRow(source, color: Self.dotColors[sourceIndex % Self.dotColors.count])
          }
        }
      }

      if !message.isThinking, let details = message.details {
        Text([details.scopeLabel, details.modelLabel.map { "\(details.engineLabel) · \($0)" } ?? details.engineLabel].joined(separator: "・"))
          .font(.caption2)
          .foregroundStyle(.tertiary)
          .padding(.top, 4)
          .padding(.leading, 22)
      }
    }
    .padding(.leading, 14)
    .overlay(alignment: .leading) {
      // The thread the rows hang from.
      Rectangle()
        .fill(.quaternary)
        .frame(width: 1)
        .padding(.leading, 6)
        .padding(.vertical, 4)
    }
  }

  private func stepRow(_ step: AgentStep) -> some View {
    HStack(spacing: 8) {
      stateMark(step.state)
        .frame(width: 14)
      Text(step.title)
        .font(.footnote.weight(.medium))
        .foregroundStyle(step.state == .declined ? .secondary : .primary)
        .strikethrough(step.state == .declined)
        .lineLimit(2)
      if let detail = step.detail, !detail.isEmpty {
        Text(detail)
          .font(.caption)
          .foregroundStyle(.tertiary)
          .lineLimit(1)
      }
    }
    .frame(minHeight: 26, alignment: .leading)
    .transition(.opacity.combined(with: .offset(y: 6)))
    .accessibilityElement(children: .combine)
    .accessibilityValue(stateLabel(step.state))
  }

  private func sourceRow(_ source: AIChatSource, color: Color) -> some View {
    NavigationLink {
      MeetingDetailView(meetingID: source.meetingID)
    } label: {
      HStack(spacing: 8) {
        Circle()
          .fill(color)
          .frame(width: 8, height: 8)
          .frame(width: 14)
        Text(source.title)
          .font(.footnote)
          .foregroundStyle(.primary)
          .underline(color: .secondary.opacity(0.4))
          .lineLimit(1)
        if !source.excerpts.isEmpty {
          Text("\(source.excerpts.count)か所")
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
      }
      .frame(minHeight: 26, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .transition(.opacity.combined(with: .offset(y: 6)))
    .accessibilityHint("記録を開きます")
  }

  @ViewBuilder
  private func stateMark(_ state: AgentStep.State) -> some View {
    switch state {
    case .running:
      ProgressView()
        .controlSize(.mini)
    case .done:
      Image(icon: .checkmark)
        .font(.caption2.weight(.bold))
        .foregroundStyle(.tertiary)
    case .declined:
      Image(icon: .xmark)
        .font(.caption2.weight(.bold))
        .foregroundStyle(.tertiary)
    case .failed:
      Image(icon: .exclamationmarkTriangle)
        .font(.caption2)
        .foregroundStyle(.orange)
    }
  }

  private func stateLabel(_ state: AgentStep.State) -> String {
    switch state {
    case .running: "実行中"
    case .done: "完了"
    case .declined: "取りやめ"
    case .failed: "失敗"
    }
  }
}
