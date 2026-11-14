import Foundation

@main
struct ReadabilityGuideChecks {
  static func main() {
    precondition(ReadabilityGuide.yomiyasuVersion == "2.4.0")
    precondition(ReadabilityGuide.yomiyasuRevision.count == 40)
    precondition(ReadabilityGuide.yomiyasuRevision == "ae258d7a57b335673e30b88a018ae08d4f72c449")
    for rule in ["通知先・依頼先", "一覧の頭→先頭", "通常の文章にはこの省略を適用せず", "引用"] {
      precondition(ReadabilityGuide.rules.contains(rule), "Missing 2.4.0 preservation rule: \(rule)")
    }
    for rule in ["意味の保持", "発言者", "担当未定", "確認済みの結果", "見出し", "限定", "スキーマ", "時制", "助詞", "形式名詞"] {
      precondition(ReadabilityGuide.rules.contains(rule), "Missing cloud rule: \(rule)")
    }
    for rule in ["連用形名詞", "専門用語", "原文", "確度"] {
      precondition((ReadabilityGuide.rules + ReadabilityGuide.compactRules).contains(rule))
    }
    for rule in ["条件付き合意", "相槌", "記載なし", "依存条件"] {
      precondition(ReadabilityGuide.summaryRules.contains(rule))
    }
    for rule in ["条件", "発言者", "担当未定", "確認済みの結果", "通常の抽出観点は見出しの強制ではない", "空行", "太字"] {
      precondition(ReadabilityGuide.compactRules.contains(rule), "Missing compact rule: \(rule)")
    }
    print("ReadabilityGuide checks passed")
  }
}
