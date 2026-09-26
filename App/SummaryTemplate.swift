import Foundation

enum SummaryTemplate: String, CaseIterable, Identifiable {
  case automatic
  case meetingMinutes
  case detailedMinutes
  case actionPlan

  var id: Self { self }

  var title: String {
    switch self {
    case .automatic: "自動"
    case .meetingMinutes: "議事録"
    case .detailedMinutes: "詳細な議事録"
    case .actionPlan: "アクション中心"
    }
  }

  var detail: String {
    switch self {
    case .automatic: "内容に合わせて最適な形に整理"
    case .meetingMinutes: "要点・決定・未決事項を簡潔に整理"
    case .detailedMinutes: "話題の流れと背景を詳しく残す"
    case .actionPlan: "担当と次にすることを中心に抽出"
    }
  }

  var processingLabel: String {
    switch self {
    case .automatic: "内容に合う形で要約中"
    case .meetingMinutes: "議事録を生成中"
    case .detailedMinutes: "詳細な議事録を生成中"
    case .actionPlan: "次の行動を整理中"
    }
  }

  var symbol: MemoraIcon {
    switch self {
    case .automatic: .sparkles
    case .meetingMinutes: .textDocument
    case .detailedMinutes: .listBulletRectangle
    case .actionPlan: .checkmarkCircle
    }
  }
}
