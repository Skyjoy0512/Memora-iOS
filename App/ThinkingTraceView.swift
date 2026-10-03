import SwiftUI

/// What the AI really did on the way to a reply, as an expandable trace. Each
/// pattern appears only when that work actually happened:
/// - Search: a record or mail search ran — its terms and what it found.
/// - Steps: the agent ran tools — one row per tool, spinner to check.
/// - Reasoning: the model returned its reasoning text — shown as written.
/// A reply with none of these shows no trace at all.
struct ThinkingTraceView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var message: AIChatMessage
  /// Set by a tap; until then the trace opens while working and closes after.
  @State private var manualExpanded: Bool?

  private static let dotColors: [Color] = [.accentColor, .orange, .green]
  /// How many search results are listed before "+N件".
  private static let resultLimit = 5

  /// Whether there is anything real to show, or something under way.
  static func hasTrace(_ message: AIChatMessage) -> Bool {
    message.isThinking
      || !message.agentSteps.isEmpty
      || !message.reasoning.isEmpty
      || (!message.isAgentReply && message.searchFinished)
  }

  var body: some View {
    let isWaitingForApproval = model.pendingAgentApproval?.messageID == message.id
      || model.pendingAgentQuestions?.messageID == message.id
    let working = message.isThinking && !isWaitingForApproval
    let canExpand = hasRows
    let expanded = canExpand && (manualExpanded ?? (message.isThinking || isWaitingForApproval))

    VStack(alignment: .leading, spacing: 4) {
      Button {
        guard canExpand else { return }
        withAnimation(reduceMotion ? nil : MemoraMotion.screen) {
          manualExpanded = !expanded
        }
      } label: {
        HStack(spacing: 8) {
          if working {
            PixelLoader(pattern: message.isAgentReply ? .orbit : .drive)
          } else {
            Image(icon: headerIcon)
              .font(.footnote)
              .foregroundStyle(.tertiary)
          }
          Group {
            if working {
              HStack(spacing: 8) {
                ShimmerText(text: activeLabel)
                // The time since the question was sent, ticking for real.
                ElapsedText(since: message.createdAt)
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(.tertiary)
              }
            } else {
              Text(isWaitingForApproval ? "確認を待っています" : doneLabel)
                .foregroundStyle(.secondary)
                .transition(.opacity)
            }
          }
          .font(.footnote.weight(.medium))
          if canExpand {
            Image(icon: .chevronDown)
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.tertiary)
              .rotationEffect(.degrees(expanded ? 180 : 0))
          }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(!canExpand)
      .accessibilityLabel(working ? activeLabel : doneLabel)
      .accessibilityValue(canExpand ? (expanded ? "開いています" : "閉じています") : "")

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

  // MARK: - What there is to show

  private var isSearchAnswer: Bool { !message.isAgentReply }

  private var hasRows: Bool {
    if isSearchAnswer { return message.traceQuery != nil || !message.sources.isEmpty }
    return !message.agentSteps.isEmpty || !message.reasoning.isEmpty
  }

  private var headerIcon: MemoraIcon {
    if isSearchAnswer { return .magnifyingglass }
    return message.agentSteps.isEmpty ? .sparkles : .checklist
  }

  private var activeLabel: String {
    if isSearchAnswer {
      return message.searchFinished ? "回答を書いています" : "記録を探しています"
    }
    if let running = message.agentSteps.last(where: { $0.state == .running }) {
      return running.title
    }
    return message.agentSteps.isEmpty ? "考えています" : "作業しています"
  }

  private var doneLabel: String {
    let seconds = message.elapsedSeconds.map { "\($0)秒" }
    if isSearchAnswer {
      guard message.searchFinished else { return "回答できませんでした" }
      let read = message.sources.isEmpty ? "該当する記録はありませんでした" : "\(message.sources.count)件の記録を参照"
      return [read, seconds].compactMap { $0 }.joined(separator: "・")
    }
    let done = message.agentSteps.filter { $0.state == .done }.count
    if done > 0 {
      return ["\(done)個の作業", seconds].compactMap { $0 }.joined(separator: "・")
    }
    return seconds.map { "\($0)考えました" } ?? "考えました"
  }

  // MARK: - Trace

  private var trace: some View {
    VStack(alignment: .leading, spacing: 2) {
      if isSearchAnswer {
        if let query = message.traceQuery {
          queryRow(query)
        }
        resultRows(message.sources.map {
          AgentStep.Result(title: $0.title, subtitle: $0.excerpts.isEmpty ? nil : "\($0.excerpts.count)か所", meetingID: $0.meetingID)
        })
        if !message.isThinking, let details = message.details {
          Text([details.scopeLabel, details.modelLabel.map { "\(details.engineLabel) · \($0)" } ?? details.engineLabel].joined(separator: "・"))
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, 4)
            .padding(.leading, 22)
        }
      } else {
        if !message.reasoning.isEmpty {
          // The model's own words, only because it returned them.
          Text(message.reasoning)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineSpacing(3)
            .lineLimit(12)
            .padding(.vertical, 4)
            .padding(.leading, 22)
            .textSelection(.enabled)
            .transition(.opacity)
        }
        ForEach(message.agentSteps) { step in
          stepRow(step)
          if let query = step.query {
            queryRow(query)
              .padding(.leading, 22)
          }
          if !step.results.isEmpty {
            resultRows(step.results)
              .padding(.leading, 22)
          }
        }
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

  private func queryRow(_ query: String) -> some View {
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

  @ViewBuilder
  private func resultRows(_ results: [AgentStep.Result]) -> some View {
    ForEach(Array(results.prefix(Self.resultLimit).enumerated()), id: \.offset) { index, result in
      resultRow(result, color: Self.dotColors[index % Self.dotColors.count])
    }
    if results.count > Self.resultLimit {
      Text("ほか\(results.count - Self.resultLimit)件")
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(.leading, 22)
        .frame(minHeight: 22)
    }
  }

  @ViewBuilder
  private func resultRow(_ result: AgentStep.Result, color: Color) -> some View {
    let label = HStack(spacing: 8) {
      Circle()
        .fill(color)
        .frame(width: 8, height: 8)
        .frame(width: 14)
      Text(result.title)
        .font(.footnote)
        .foregroundStyle(.primary)
        .underline(result.meetingID != nil, color: .secondary.opacity(0.4))
        .lineLimit(1)
      if let subtitle = result.subtitle {
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.tertiary)
          .lineLimit(1)
      }
    }
    .frame(minHeight: 26, alignment: .leading)
    .contentShape(Rectangle())
    .transition(.opacity.combined(with: .offset(y: 6)))

    if let meetingID = result.meetingID {
      NavigationLink {
        MeetingDetailView(meetingID: meetingID)
      } label: {
        label
      }
      .buttonStyle(.plain)
      .accessibilityHint("記録を開きます")
    } else {
      label
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
