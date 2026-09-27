import SwiftUI

enum OnboardingPage: String, CaseIterable, Identifiable, Hashable {
  case record
  case understand
  case act

  var id: Self { self }

  var symbol: MemoraIcon {
    switch self {
    case .record:
      .waveform
    case .understand:
      .textAlignleft
    case .act:
      .checkmark
    }
  }

  var title: String {
    switch self {
    case .record:
      "話すだけで、\nあとは任せる。"
    case .understand:
      "終わった瞬間に、\n要点と決定だけ。"
    case .act:
      "次にすることが、\nそのまま残る。"
    }
  }

  var detail: String {
    switch self {
    case .record:
      "会議が始まったら録音を押すだけ。設定も準備もいりません。"
    case .understand:
      "サマリー・決定・未決事項へ自動で整理し、元の発言まで戻れます。"
    case .act:
      "会話から見つかったタスクが集まり、担当と期限まで揃います。"
    }
  }

  var next: OnboardingPage? {
    let all = Self.allCases
    guard let index = all.firstIndex(of: self), index + 1 < all.count else { return nil }
    return all[index + 1]
  }
}
