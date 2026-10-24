import Foundation

@main
struct ReadabilityGuideChecks {
  static func main() {
    precondition(ReadabilityGuide.yomiyasuVersion == "2.3.0")
    precondition(ReadabilityGuide.yomiyasuRevision.count == 40)
    for rule in ["意味の保持", "発言者", "担当未定", "確認済みの結果", "見出し", "限定", "スキーマ", "時制", "助詞", "形式名詞"] {
      precondition(ReadabilityGuide.rules.contains(rule), "Missing cloud rule: \(rule)")
    }
    for rule in ["連用形名詞", "専門用語", "原文", "確度"] {
      precondition((ReadabilityGuide.rules + ReadabilityGuide.compactRules).contains(rule))
    }
    for rule in ["条件付き合意", "相槌", "記載なし", "依存条件"] {
      precondition(ReadabilityGuide.summaryRules.contains(rule))
    }
    for rule in ["条件", "発言者", "担当未定", "確認済みの結果", "テンプレート", "空行", "太字"] {
      precondition(ReadabilityGuide.compactRules.contains(rule), "Missing compact rule: \(rule)")
    }
    print("ReadabilityGuide checks passed")
  }
}
