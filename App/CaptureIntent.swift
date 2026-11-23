import Foundation

/// One normalized thing the person brought in, whatever the entry point was.
enum CaptureIntent: Hashable, Sendable {
  /// A public web link.
  case url(URL)
  /// Text the person copied.
  case text(String)
  /// A compressed image.
  case image(Data)
  /// A file inside the app container.
  case file(URL)
  /// An audio file to transcribe.
  case audio(URL)
  /// A meeting to keep as a record.
  case meeting(URL)

  /// The name a person would recognize.
  var displayName: String {
    switch self {
    case .url: "リンク"
    case .text: "テキスト"
    case .image: "写真"
    case .file: "ファイル"
    case .audio: "音声"
    case .meeting: "会議"
    }
  }

  /// The kind of source this becomes in the workspace.
  var kind: ProjectSource.Kind {
    switch self {
    case .url, .meeting: .web
    case .text: .note
    case .image: .image
    case .file: .document
    case .audio: .audio
    }
  }

  /// A text intent that keeps at most the first 10,000 characters.
  static func note(_ value: String) -> CaptureIntent {
    .text(String(value.prefix(10_000)))
  }
}
