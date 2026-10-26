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
      "会話を、忘れない記録に。"
    case .understand:
      "長い会話から、大切なことを。"
    case .act:
      "会議のあとを、次の仕事へ。"
    }
  }

  var detail: String {
    switch self {
    case .record:
      "まずは録音。マイクの許可は、録音を始めるときに確認します。"
    case .understand:
      "文字起こしと要約で、決定・未決事項を整理。元の発言も確認できます。"
    case .act:
      "記録にある作業をタスクへ。担当者や期限は、会話で決まった内容だけ。"
    }
  }

  var next: OnboardingPage? {
    let all = Self.allCases
    guard let index = all.firstIndex(of: self), index + 1 < all.count else { return nil }
    return all[index + 1]
  }
}
