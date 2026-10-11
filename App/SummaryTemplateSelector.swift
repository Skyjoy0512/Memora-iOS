import Foundation

enum SummaryTemplateSelector {
  static func preferredTemplateID(explicitID: String?, recommendedIDs: [String],
                                  availableIDs: Set<String>, fallbackID: String) -> String {
    if let explicitID {
      return availableIDs.contains(explicitID) ? explicitID : fallbackID
    }
    return recommendedIDs.first(where: availableIDs.contains) ?? fallbackID
  }

  static func contentTemplateID(_ text: String) -> String? {
    let rules: [(String, [String])] = [
      ("market.regular", ["スタッフ配置", "スタッフ会議", "定例会議", "議題", "体制に"]),
      ("work.customer-chart", ["毛先", "前髪", "ヘアカラー", "カラーも", "髪を", "カットして"]),
      ("work.shift-handover", ["移動介助", "食事介助", "申し送り", "次の担当", "明日の担当", "服薬"]),
      ("work.daily", ["配管工事", "電気工事", "部材", "施工", "資材", "現場作業"]),
      ("work.learning", ["講義", "授業の内容", "試験対策", "復習", "講師"]),
      ("work.journal", ["公園に", "休日", "散歩", "家族と", "楽しかった", "買い物に"])
    ]
    let scored = rules.map { rule in
      (rule.0, rule.1.filter { text.localizedStandardContains($0) }.count)
    }
    guard let winner = scored.max(by: { $0.1 < $1.1 }), winner.1 >= 2,
          scored.filter({ $0.1 == winner.1 }).count == 1 else { return nil }
    return winner.0
  }
}
