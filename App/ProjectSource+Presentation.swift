import Foundation

extension ProjectSource {
  var kindLabel: String {
    switch kind {
    case .youtube: "YouTube"
    case .video: "動画"
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
    case .youtube, .video: .video
    case .web: .link
    case .image: .photo
    case .pdf, .document: .docText
    case .audio: .waveform
    case .note: .noteText
    }
  }

  var statusLabel: String {
    switch processingStatus {
    case .pending, .processing: "準備中"
    case .ready:
      if summaryStatus == .ready, summaryTextReference == extractedTextReference { "要約あり" }
      else if !canProvideText { "保存済み" }
      else if textCoverage == .partial { "本文あり · 一部の内容" }
      else { "本文あり" }
    case .unavailable:
      if kind == .youtube, metadata?["youtubeTitle"] != nil { String(localized: "動画リンク") }
      else { "保存済み · 内容未取得" }
    case .failed: "保存済み · 要確認"
    }
  }

  var availabilityNotice: String? {
    if kind == .youtube, !canProvideText {
      let notice = metadata?["youtubeTitle"] == nil
        ? "動画リンクを保存しています。動画の音声・字幕は取得していません。"
        : "タイトルなどの動画情報だけを取得しています。動画の音声・字幕は取得していません。"
      return [errorInformation, notice].compactMap { $0 }.joined(separator: "\n")
    }
    if let errorInformation { return errorInformation }
    if kind == .web, !canProvideText {
      return "URLのみ保存しています。Webページの本文は取得していません。"
    }
    if canProvideText, textCoverage == nil {
      return "以前の解析結果です。全文を読み取れたかは確認できません。"
    }
    return nil
  }

  var webFetchedAt: Date? {
    guard kind == .web, let value = metadata?["webFetchedAt"] else { return nil }
    return ISO8601DateFormatter().date(from: value)
  }
}
