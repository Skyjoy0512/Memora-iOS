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
      .circle
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
      "会議や思いつきを音声で残せます。"
    case .understand:
      "文字起こしと要約から、発言や決定を振り返れます。"
    case .act:
      "会話の中で決まった作業を、タスクとして残せます。"
    }
  }

  var next: OnboardingPage? {
    switch self {
    case .record: .understand
    case .understand: .act
    case .act: nil
    }
  }

  var previous: OnboardingPage? {
    switch self {
    case .record: nil
    case .understand: .record
    case .act: .understand
    }
  }

  var number: Int {
    switch self {
    case .record: 1
    case .understand: 2
    case .act: 3
    }
  }
}
