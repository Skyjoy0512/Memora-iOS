import Foundation

/// The built-in shapes a summary can take. 詳細な概要 is the base every
/// automatic summary uses; the others are picked from the custom list.
enum SummaryTemplate: String, CaseIterable, Identifiable, Codable {
  case detailedOverview
  case meetingMinutes
  case detailedMinutes
  case actionPlan

  var id: Self { self }

  var title: String {
    switch self {
    case .detailedOverview: "詳細な概要"
    case .meetingMinutes: "議事録"
    case .detailedMinutes: "時系列の議事録"
    case .actionPlan: "アクション中心"
    }
  }

  var detail: String {
    switch self {
    case .detailedOverview: "トピックごとに要点・決定事項・アクション・未決事項を整理"
    case .meetingMinutes: "会議情報・話題ごとの議事メモ・アクションを簡潔に整理"
    case .detailedMinutes: "時間の区切りごとに話の流れと決定の理由を残す"
    case .actionPlan: "担当と期限のあるアクションを中心に抽出"
    }
  }

  var processingLabel: String {
    switch self {
    case .detailedOverview: "詳細な概要を作成中"
    case .meetingMinutes: "議事録を生成中"
    case .detailedMinutes: "時系列の議事録を生成中"
    case .actionPlan: "次の行動を整理中"
    }
  }

  var symbol: MemoraIcon {
    switch self {
    case .detailedOverview: .sparkles
    case .meetingMinutes: .textDocument
    case .detailedMinutes: .listBulletRectangle
    case .actionPlan: .checkmarkCircle
    }
  }
}
