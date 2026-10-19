@main
struct AIPluginMenuCopyChecks {
  static func main() {
    let fileSummary = AIPluginMenuCopy.summary(id: "tool:memora:search_records", fallback: "query / id / title")
    precondition(fileSummary == "会議の記録やジャーナルから、関連する情報を探します。")
    precondition(!fileSummary.contains("query"))
    precondition(AIPluginMenuCopy.summary(id: "tool:memora:search_web", fallback: "schema").contains("出典"))
    precondition(AIPluginMenuCopy.summary(id: "tool:memora:deep_research", fallback: "schema").contains("複数"))
    for id in ["skill:custom", "mcp:server", "record:uuid", "source:uuid", "service:calendar"] {
      let custom = "利用者の説明・日本語 📝"
      precondition(AIPluginMenuCopy.summary(id: id, fallback: custom) == custom)
      precondition(AIPluginMenuCopy.summary(id: id, fallback: "").isEmpty)
    }
    print("AIPluginMenuCopyChecks passed: concise builtin copy, original custom/MCP/record descriptions preserved")
  }
}
