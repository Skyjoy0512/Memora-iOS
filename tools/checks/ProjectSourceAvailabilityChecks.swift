import Foundation

@main
struct ProjectSourceAvailabilityChecks {
  static func main() throws {
    var source = ProjectSource(kind: .web, title: "保存したリンク")
    precondition(source.statusLabel.contains("内容未取得") && source.availabilityNotice != nil)
    source.kind = .pdf
    source.processingStatus = .ready
    precondition(!source.canProvideText && source.statusLabel == "内容未取得")
    source.extractedTextReference = "bounded.json"
    precondition(source.canProvideText && source.statusLabel.contains("解析範囲未確認"))
    source.textCoverage = .partial
    precondition(source.canProvideText && source.statusLabel == "一部をAI参照可")
    let partial = try JSONDecoder().decode(ProjectSource.self, from: JSONEncoder().encode(source))
    precondition(partial == source && !partial.privacy.allowsCloudAI)
    source.textCoverage = .complete
    precondition(source.statusLabel == "AI参照可")
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as! [String: Any]
    legacy.removeValue(forKey: "textCoverage")
    let restored = try JSONDecoder().decode(ProjectSource.self, from: JSONSerialization.data(withJSONObject: legacy))
    precondition(restored.textCoverage == nil && restored.canProvideText && restored.availabilityNotice != nil)
    precondition(restored.processingStatus == .ready && restored.extractedTextReference == source.extractedTextReference)
    for status in [ProjectSource.ProcessingStatus.pending, .processing, .unavailable, .failed] {
      source.processingStatus = status
      precondition(!source.canProvideText)
    }
    print("ProjectSourceAvailabilityChecks: passed (legacy codec, honest partial/missing states, unchanged privacy and evidence eligibility)")
  }
}
