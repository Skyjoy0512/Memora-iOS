import SwiftUI

struct ProcessingOverview: View {
  @Environment(MemoraModel.self) private var model
  var meeting: Meeting

  var body: some View {
    let isVideo = meeting.usesVideoSummary || model.pendingSummaryJobs.contains {
      $0.meetingID == meeting.id && $0.choice.id == VideoSummaryTemplate.template.id
    }
    return VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 6) {
        WorkingStatus(label: primaryText, startedAt: model.processing.startedAt[meeting.id])
      }

      VStack(alignment: .leading, spacing: 12) {
        if meeting.audioURL != nil {
          ProcessStep(title: "音声を保存", isComplete: true, isCurrent: false)
          ProcessStep(title: "文字にする", isComplete: hasTranscript, isCurrent: !hasTranscript)
        } else {
          ProcessStep(title: "原文を保存", isComplete: hasTranscript, isCurrent: !hasTranscript)
        }
        ProcessStep(title: isVideo ? "動画の内容を整理" : "要点と行動を整理", isComplete: false, isCurrent: isOrganizing)
      }
    }
    .padding(MemoraSpacing.lg)
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

