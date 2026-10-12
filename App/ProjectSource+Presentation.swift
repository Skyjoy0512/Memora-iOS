import Foundation

extension ProjectSource {
  var kindLabel: String {
    switch kind {
    case .youtube: "YouTube"
    case .web: "Web"
    case .image: "画像"
    case .pdf: "PDF"
    case .document: "文書"
    case .audio: "音声"
    case .note: "メモ"
    }
  }

  var icon: MemoraIcon {
    switch kind {
    case .youtube: .video
    case .web: .link
    case .image: .photo
    case .pdf, .document: .docText
    case .audio: .waveform
    case .note: .noteText
    }
  }

  var statusLabel: String {
    switch processingStatus {
    case .pending: "保存済み · 解析待ち"
    case .processing: "解析中"
    case .ready: "AI参照可能"
    case .unavailable: "保存済み · 解析不可"
    case .failed: "保存済み · 解析失敗"
    }
  }
}
