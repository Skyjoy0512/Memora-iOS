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
      "会話を録音する"
    case .understand:
      "あとから読み返す"
    case .act:
      "タスクにつなげる"
    }
  }

  var detail: String {
    switch self {
    case .record:
      "会議や思いついたことを、音声で残せます。"
    case .understand:
      "文字起こしと要約で、決まったことや元の発言を確認できます。"
    case .act:
      "会話で決まった作業をタスクにできます。"
    }
  }

  var next: OnboardingPage? {
    let all = Self.allCases
    guard let index = all.firstIndex(of: self), index + 1 < all.count else { return nil }
    return all[index + 1]
  }
}
