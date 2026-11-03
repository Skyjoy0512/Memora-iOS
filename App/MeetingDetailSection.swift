enum MeetingDetailSection: String, CaseIterable, Identifiable {
  case summary
  case transcript
  case notes

  var id: Self { self }

  var label: String {
    switch self {
    case .summary: "要約"
    case .transcript: "文字起こし"
    case .notes: "ノート"
    }
  }
}
