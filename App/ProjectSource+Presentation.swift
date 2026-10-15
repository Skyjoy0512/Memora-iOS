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
    case .pending:
      if kind == .web { "リンク保存済み · 内容未取得" }
      else { kind == .youtube ? "動画リンク保存済み" : "追加済み · 解析待ち" }
    case .processing: kind == .youtube ? "動画情報を取得中" : "解析中"
    case .ready:
      if !canProvideText { "内容未取得" }
      else {
        switch textCoverage {
        case .complete: "AI参照可"
        case .partial: "一部をAI参照可"
        case nil: "AI参照可 · 解析範囲未確認"
        }
      }
    case .unavailable: "保存済み · 内容未取得"
    case .failed: "保存済み · 解析失敗"
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
