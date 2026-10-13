import Foundation

@main
struct ComposerMentionChecks {
  static func main() throws {
    func parse(_ text: String, cursor: Int? = nil, marked: Bool = false) -> ComposerMentionToken? {
      ComposerMentionToken.parse(text: text, selection: NSRange(location: cursor ?? text.utf16.count, length: 0), hasMarkedText: marked)
    }
    precondition(parse("@")?.query == "")
    precondition(parse("本文 @G")?.query == "G")
    precondition(parse("本文 @ジャーナル")?.query == "ジャーナル")
    precondition(parse("😀 @G")?.range.location == 3)
    precondition(parse("@Gmail 明日の予定", cursor: 3)?.range == NSRange(location: 0, length: 6))
    precondition(parse("a@example.com") == nil)
    precondition(parse("foo+tag@gmail") == nil)
    precondition(parse("https://user@host") == nil)
    precondition(parse("本文 @G", marked: true) == nil)
    precondition(parse("G") == nil)
    precondition(parse("[@Gmail]") == nil)
    precondition(parse("@Gmail ") == nil)
    precondition(ComposerMentionToken.parse(text: "@G", selection: NSRange(location: 0, length: 2), hasMarkedText: false) == nil)
    precondition(parse("@G", cursor: 100) == nil)
    let text = "前文 [@Gmail] 本文"
    let range = (text as NSString).range(of: "[@Gmail]")
    let mention = ComposerMention(pluginID: "service:gmail", label: "Gmail", range: range)
    let shifted = ComposerMention.reconciled([mention], from: text, to: "😀" + text)
    precondition(shifted.first?.range.location == range.location + 2)
    precondition(shifted.first?.pluginID == "service:gmail")
    precondition(ComposerMention.reconciled([mention], from: text, to: text + "続き") == [mention])
    precondition(ComposerMention.reconciled([mention], from: text, to: text.replacingOccurrences(of: "Gmail", with: "Mail")).isEmpty)
    precondition(ComposerMention.reconciled([mention], from: text, to: "前文  本文").isEmpty)
    let restored = try JSONDecoder().decode([ComposerMention].self, from: JSONEncoder().encode([mention]))
    precondition(restored == [mention])
    let record = UUID()
    let policy = AIPluginExecutionPolicy(pluginIDs: ["service:gmail", "record:" + record.uuidString], toolIDs: ["memora:search_email", "memora:read_email", "memora:read_record", "mcp_one"], recordIDs: [record], limitsRecordReads: true)
    precondition(policy.permits("search_email", arguments: [:]))
    precondition(!policy.permits("save_to_notion", arguments: [:]))
    precondition(!policy.permits("delegate_research", arguments: [:]))
    precondition(!policy.permits("mcp_other", arguments: [:]))
    precondition(policy.permits("mcp_one", arguments: [:]))
    precondition(policy.permits("read_record", arguments: ["id": record.uuidString]))
    precondition(!policy.permits("read_record", arguments: ["id": UUID().uuidString]))
    precondition(!policy.permits("read_record", arguments: ["id": "bad"]))
    var registry = AIToolRegistry()
    let schema = Data(#"{"type":"object","properties":{"id":{"type":"string"}},"required":["id"],"additionalProperties":false}"#.utf8)
    _ = registry.register(AIToolDefinition(id: "memora:read_record", name: "read_record", summary: "fixture", inputSchema: schema, provider: .memora, requiredPermissions: ["memora.read"], risk: .read, isAvailable: true, isEnabled: true))
    precondition(registry.permits("read_record", arguments: ["id": record.uuidString], policy: policy))
    precondition(!registry.permits("read_record", arguments: ["id": UUID().uuidString], policy: policy))
    precondition(!registry.permits("read_record", arguments: ["id": 42], policy: policy))
    registry.tools["memora:read_record"]?.isEnabled = false
    precondition(!registry.permits("read_record", arguments: ["id": record.uuidString], policy: policy))
    precondition(ExternalToolFailure.http(401).localizedDescription.contains("認証"))
    precondition(ExternalToolFailure.http(403).localizedDescription.contains("権限"))
    precondition(ExternalToolFailure.http(429).localizedDescription.contains("上限"))
    precondition(!ExternalToolFailure.message(for: MCPClientError.server("SECRET")).contains("SECRET"))
    print("ComposerMentionChecks passed (parser, IME refusal, editing, draft IDs, tool/record restrictions)")
  }
}
