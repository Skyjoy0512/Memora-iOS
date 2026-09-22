import Foundation

/// The paid tiers. Billing is not connected yet, so a tier is a local choice
/// that decides which features this device unlocks; the plan screen says so.
enum PlanTier: String, CaseIterable, Identifiable {
  case personal
  case team

  var id: Self { self }

  var label: String {
    switch self {
    case .personal: "個人プラン"
    case .team: "チームプラン"
    }
  }

  var symbol: String {
    switch self {
    case .personal: "person.fill"
    case .team: "person.3.fill"
    }
  }

  var tagline: String {
    switch self {
    case .personal: "自分の会議を、自分だけのために。"
    case .team: "チームの会議を、チームで共有する。"
    }
  }

  var features: [String] {
    switch self {
    case .personal:
      [
        "高度なAI整理を制限なく",
        "複数会議をまとめて質問",
        "クラウド保存と同期"
      ]
    case .team:
      [
        "個人プランのすべて",
        "選んだファイルをチーム用に書き出す",
        "チームのメンバーと共有（準備中）"
      ]
    }
  }
}
