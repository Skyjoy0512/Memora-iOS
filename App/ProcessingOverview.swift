import SwiftUI

struct ProcessingOverview: View {
  @Environment(MemoraModel.self) private var model
  var meeting: Meeting

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 6) {
        WorkingStatus(label: primaryText, startedAt: model.processing.startedAt[meeting.id])
        Text("終わった内容から順に使えるようになります")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      VStack(alignment: .leading, spacing: 12) {
        ProcessStep(title: "音声を保存", isComplete: true, isCurrent: false)
        ProcessStep(title: "文字にする", isComplete: hasTranscript, isCurrent: !hasTranscript)
        ProcessStep(title: "要点と行動を整理", isComplete: false, isCurrent: isOrganizing)
      }
    }
    .padding(18)
    .memoraCard()
  }

  private var primaryText: String {
    switch meeting.status {
    case .importing:
      "音声を読み込んでいます"
    case .transcribing:
      "会話を文字にしています"
    case .organizing(let detail):
      detail
    default:
      "内容を整理しています"
    }
  }

  private var hasTranscript: Bool {
    !meeting.transcript.isEmpty
  }

  private var isOrganizing: Bool {
    if case .organizing = meeting.status { return true }
    return false
  }
}

private struct ProcessStep: View {
  var title: String
  var isComplete: Bool
  var isCurrent: Bool

  var body: some View {
    HStack(spacing: 10) {
      Image(icon: isComplete ? .checkmarkCircleFill : isCurrent ? .circleDotted : .circle)
        .foregroundStyle(.primary)
      Text(title)
        .font(.subheadline)
        .foregroundStyle(isCurrent || isComplete ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
    }
  }
}

