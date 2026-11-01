import Foundation

@main
struct ProjectSourceAvailabilityChecks {
  static func main() throws {
    var source = ProjectSource(kind: .web, title: "保存したリンク")
    precondition(source.statusLabel == "準備中" && source.availabilityNotice != nil)
    source.kind = .pdf
    source.processingStatus = .ready
    precondition(!source.canProvideText && source.statusLabel == "保存済み")
    source.extractedTextReference = "bounded.json"
    precondition(source.canProvideText && source.statusLabel == "本文あり")
    source.textCoverage = .partial
    precondition(source.canProvideText && source.statusLabel == "本文あり · 一部の内容")
    let partial = try JSONDecoder().decode(ProjectSource.self, from: JSONEncoder().encode(source))
    precondition(partial == source && !partial.privacy.allowsCloudAI)
    source.textCoverage = .complete
    precondition(source.statusLabel == "本文あり")
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as! [String: Any]
    legacy.removeValue(forKey: "textCoverage")
    let restored = try JSONDecoder().decode(ProjectSource.self, from: JSONSerialization.data(withJSONObject: legacy))
    precondition(restored.textCoverage == nil && restored.canProvideText && restored.availabilityNotice != nil)
    precondition(restored.processingStatus == .ready && restored.extractedTextReference == source.extractedTextReference)
    for status in [ProjectSource.ProcessingStatus.pending, .processing, .unavailable, .failed] {
      source.processingStatus = status
      precondition(!source.canProvideText)
    }
    source.kind = .youtube
    source.metadata = ["youtubeTitle": "架空の動画"]
    source.processingStatus = .unavailable
    source.errorInformation = "サムネイルを取得できませんでした。"
    precondition(source.availabilityNotice?.contains("音声・字幕は取得していません") == true)
    precondition(source.availabilityNotice?.contains("サムネイル") == true)
    precondition(!source.canProvideText)
    precondition(source.statusLabel == "動画リンク" && !source.privacy.allowsCloudAI)
    for kind in [ProjectSource.Kind.pdf, .image, .document, .web, .note] {
      source.kind = kind
      for status in [ProjectSource.ProcessingStatus.pending, .processing, .unavailable, .failed] {
        source.processingStatus = status
        precondition(!source.canProvideText && !source.statusLabel.contains("解析済み"))
      }
    }
    print("ProjectSourceAvailabilityChecks: passed (legacy codec, honest partial/missing states, unchanged privacy and evidence eligibility)")
  }
}
