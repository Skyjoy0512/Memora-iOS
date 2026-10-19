/// Presentation copy is separate from tool instructions and search keywords.
enum AIPluginMenuCopy {
  static func summary(id: String, fallback: String) -> String {
    switch id {
    case "tool:memora:search_records": "会議の記録やジャーナルから、関連する情報を探します。"
    case "tool:memora:search_web": "Webから情報を探し、出典を確認します。"
    case "tool:memora:deep_research": "複数の情報源を調べ、出典付きで整理します。"
    default: fallback
    }
  }
}
