enum CaptureSheetAction: CaseIterable, Identifiable {
  case camera, photos, files, link
  case recording, importAudio, onlineMeeting, newNote

  var id: Self { self }

  var title: String {
    switch self {
    case .camera: "カメラ"
    case .photos: "写真"
    case .files: "ファイル"
    case .link: "リンク"
    case .recording: "録音する"
    case .importAudio: "音声を取り込む"
    case .onlineMeeting: "オンライン会議を録音"
    case .newNote: "ノートを追加"
    }
  }

  var icon: MemoraIcon {
    switch self {
    case .camera: .camera
    case .photos: .photoOnRectangle
    case .files: .doc
    case .link: .link
    case .recording: .waveform
    case .importAudio: .squareAndArrowDown
    case .onlineMeeting: .video
    case .newNote: .squareAndPencil
    }
  }
}
