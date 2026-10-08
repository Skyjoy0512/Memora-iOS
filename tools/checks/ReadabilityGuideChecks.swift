import Foundation

@main
struct ReadabilityGuideChecks {
  static func main() {
    precondition(ReadabilityGuide.yomiyasuVersion == "1.1.0")
    precondition(ReadabilityGuide.yomiyasuRevision.count == 40)
    for rule in ["意味の保持", "発言者", "担当未定", "確認済みの結果", "見出し", "限定", "スキーマ"] {
      precondition(ReadabilityGuide.rules.contains(rule), "Missing cloud rule: \(rule)")
    }
    for rule in ["条件", "発言者", "担当未定", "確認済みの結果", "テンプレート", "空行", "太字"] {
      precondition(ReadabilityGuide.compactRules.contains(rule), "Missing compact rule: \(rule)")
    }
    print("ReadabilityGuide checks passed")
  }
}
