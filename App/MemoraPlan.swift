import Foundation

/// The paid plans for people without their own AI key. Each one's AI credits
/// and cloud transcription are planning caps, not a profitability guarantee.
/// Annual/FX/operating-cost gates remain open in docs/PRICING.md.
/// Billing is not connected yet; a plan is a local choice and the screen says so.
enum MemoraPlan: String, CaseIterable, Identifiable, Codable {
  case light
  case pro
  case unlimited
  /// Unlimited for each member, plus the team workspace and sharing.
  case team

  var id: Self { self }

  var label: String {
    switch self {
    case .light: "ライト"
    case .pro: "Pro"
    case .unlimited: "アンリミテッド"
    case .team: "チーム"
    }
  }

  var monthlyPrice: Int {
    switch self {
    case .light: 480
    case .pro: 1_480
    case .unlimited: 2_980
    case .team: 3_480
    }
  }

  var priceLabel: String {
    self == .team ? "¥\(monthlyPrice.formatted())/人・月" : "¥\(monthlyPrice.formatted())/月"
  }

  /// Memora Intelligence credits each month. One credit is $0.005 of AI cost.
  var monthlyCredits: Int {
    switch self {
    case .light: 300
    case .pro: 800
    case .unlimited: 1_500
    case .team: 1_500
    }
  }

  /// Hours of cloud transcription each month. Transcription is on the device
  /// for now on every plan; cloud transcription costs ten times a summary, so
  /// it waits until it can be priced on its own.
  var cloudTranscriptionHours: Int { 0 }

  /// The team workspace, team sharing and shared projects.
  var includesTeam: Bool { self == .team }

  var symbol: MemoraIcon {
    switch self {
    case .light: .leafFill
    case .pro: .boltFill
    case .unlimited: .infinity
    case .team: .person3Fill
    }
  }

  var tagline: String {
    switch self {
    case .light: "端末内の文字起こしに、AIの要約と質問を足す。"
    case .pro: "長い会議もクラウドで正確に。毎日の仕事に。"
    case .unlimited: "端末内は無制限。会議の多い人に。"
    case .team: "チームの会議を、チームで共有する。"
    }
  }

  var features: [String] {
    var lines = [
      "Memora Intelligence（AI）\(monthlyCredits.formatted())クレジット/月",
      "文字起こしは端末内（無制限・音声は外に出ません）"
    ]
    switch self {
    case .light:
      lines.append("要約テンプレートとAsk AI")
    case .pro:
      lines.append("エージェント・Webhook・MCP連携")
    case .unlimited:
      lines.append("Proのすべて")
      lines.append("AIクレジットには公正利用の上限があります")
    case .team:
      lines.append("アンリミテッドのすべて（1人ごと）")
      lines.append("チームワークスペースとチーム共有")
    }
    return lines
  }
}
