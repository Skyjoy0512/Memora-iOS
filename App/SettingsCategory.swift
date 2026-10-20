/// Top-level destinations are topics; individual switches live one level below.
enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
  case account, workspace, plan, recording, ai, journal, integrations, appearance, privacy, data, about, diagnostics

  var id: String { rawValue }
  static var groups: [String] { ["アカウント", "アプリ", "データ", "その他"] }

  var group: String {
    switch self {
    case .account, .workspace, .plan: "アカウント"
    case .recording, .ai, .journal, .integrations, .appearance: "アプリ"
    case .privacy, .data: "データ"
    case .about, .diagnostics: "その他"
    }
  }

  var title: String {
    switch self {
    case .account: "アカウント"
    case .workspace: "ワークスペース"
    case .plan: "プランと利用状況"
    case .recording: "録音と文字起こし"
    case .ai: "AIと要約"
    case .journal: "ジャーナル"
    case .integrations: "連携"
    case .appearance: "表示と操作"
    case .privacy: "プライバシー"
    case .data: "データ管理"
    case .about: "ヘルプと情報"
    case .diagnostics: "診断とプレビュー"
    }
  }

  var icon: MemoraIcon {
    switch self {
    case .account: .personCropCircle
    case .workspace: .person2
    case .plan: .creditcard
    case .recording: .waveform
    case .ai: .sparkles
    case .journal: .calendar
    case .integrations: .plugsConnected
    case .appearance: .sliderHorizontal3
    case .privacy: .lockShield
    case .data: .internaldrive
    case .about: .questionmarkCircle
    case .diagnostics: .rectangleStack
    }
  }
}
