import Foundation

/// The paid plans for people without their own AI key. Each one's AI credits
/// and cloud transcription are capped so that, used to the full, its cost stays
/// below what it earns after tax and the App Store fee (docs/PRICING.md).
/// Billing is not connected yet; a plan is a local choice and the screen says so.
enum MemoraPlan: String, CaseIterable, Identifiable, Codable {
  case light
  case pro
  case unlimited

  var id: Self { self }

  var label: String {
    switch self {
    case .light: "ライト"
    case .pro: "Pro"
    case .unlimited: "アンリミテッド"
    }
  }

  var monthlyPrice: Int {
    switch self {
    case .light: 480
    case .pro: 1_480
    case .unlimited: 2_980
    }
  }

  var priceLabel: String {
    "¥\(monthlyPrice.formatted())/月"
  }

  /// Memora Intelligence credits each month. One credit is $0.005 of AI cost.
  var monthlyCredits: Int {
    switch self {
    case .light: 300
    case .pro: 800
    case .unlimited: 1_500
    }
  }

  /// Hours of cloud transcription each month; on-device is always unlimited.
  var cloudTranscriptionHours: Int {
    switch self {
    case .light: 0
    case .pro: 5
    case .unlimited: 20
    }
  }

  var symbol: MemoraIcon {
    switch self {
    case .light: .leafFill
    case .pro: .boltFill
    case .unlimited: .infinity
    }
  }

  var tagline: String {
    switch self {
    case .light: "端末内の文字起こしに、AIの要約と質問を足す。"
    case .pro: "長い会議もクラウドで正確に。毎日の仕事に。"
    case .unlimited: "端末内は無制限。会議の多い人に。"
    }
  }

  var features: [String] {
    var lines = [
      "Memora Intelligence（AI）\(monthlyCredits.formatted())クレジット/月",
      cloudTranscriptionHours == 0
        ? "文字起こしは端末内（無制限）"
        : "クラウド文字起こし\(cloudTranscriptionHours)時間/月＋端末内は無制限"
    ]
    switch self {
    case .light:
      lines.append("要約テンプレートとAsk AI")
    case .pro:
      lines.append("エージェント・Webhook・MCP連携")
    case .unlimited:
      lines.append("Proのすべて")
      lines.append("クラウド分には公正利用の上限があります")
    }
    return lines
  }
}
