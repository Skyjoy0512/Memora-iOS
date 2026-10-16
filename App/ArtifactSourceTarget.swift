import Foundation

enum ArtifactSourceTarget: Hashable, Identifiable {
  case record(RecordPrivacyTarget)
  case projectFile(UUID)
  var id: Self { self }

  var label: String {
    switch self {
    case .record(.meeting): "会議"
    case .record(.journal): "ジャーナル"
    case .record(.task): "タスク"
    case .record(.person): "人物"
    case .projectFile: "資料"
    }
  }

  var icon: MemoraIcon {
    switch self {
    case .record(.meeting): .waveform
    case .record(.journal): .textAlignleft
    case .record(.task): .checklist
    case .record(.person): .person
    case .projectFile: .docText
    }
  }
}
