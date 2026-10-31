import Foundation

/// The sections of a meeting's summary tab. Raw values key each section's
/// collapsed state, so renaming a case forgets what the user folded away.
enum MeetingInsightSection: String, CaseIterable, Identifiable {
  case summary
  case decisions
  case tasks
  case openQuestions
  case keyPoints

  var id: Self { self }

  var artwork: MemoraArtwork? {
    switch self {
    case .summary: .insightSummary
    case .openQuestions: .insightQuestion
    case .keyPoints: .insightTarget
    case .decisions, .tasks: nil
    }
  }

  var title: String {
    switch self {
    case .summary: "要約"
    case .decisions: "決まったこと"
    case .tasks: "次にすること"
    case .openQuestions: "まだ決まっていないこと"
    case .keyPoints: "重要なポイント"
    }
  }

  var icon: MemoraIcon {
    switch self {
    case .summary: .textAlignleft
    case .decisions: .checkmarkSeal
    case .tasks: .arrowRightCircle
    case .openQuestions: .questionmarkBubble
    case .keyPoints: .pin
    }
  }
}
