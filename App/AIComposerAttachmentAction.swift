import SwiftUI

enum AIComposerAttachmentAction: String, CaseIterable, Identifiable {
  case photo, audio, file, mention, integrations

  var id: Self { self }

  var title: String {
    switch self {
    case .mention: "プラグイン・スキル・ソース"
    case .integrations: "連携サービス…"
    case .photo: "写真を選択…"
    case .audio: "音声を選択…"
    case .file: "ファイルを選択…"
    }
  }

  var icon: MemoraIcon {
    switch self {
    case .mention: .puzzle
    case .integrations: .plugsConnected
    case .photo: .photo
    case .audio: .waveform
    case .file: .paperclip
    }
  }

  var displayTitle: String {
    switch self {
    case .mention: "プラグイン"
    case .integrations: "連携サービス"
    case .photo: "写真"
    case .audio: "音声"
    case .file: "ファイル"
    }
  }
}
