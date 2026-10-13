import Foundation

@main
struct ToolIntegrationChecks {
  static func main() async throws {
    let schema: [String: Any] = ["type": "object", "required": ["query"], "additionalProperties": false,
      "properties": ["query": ["type": "string", "minLength": 1, "maxLength": 10],
                     "limit": ["type": "integer", "minimum": 1, "maximum": 20]]]
    precondition(ToolInputValidator.accepts(["query": "旅行", "limit": 3], schema: schema))
    for input: [String: Any] in [[:], ["query": ""], ["query": 7], ["query": "q", "limit": true],
                               ["query": "q", "limit": 1.5], ["query": "q", "limit": 21], ["query": "q", "extra": "x"]] {
      precondition(!ToolInputValidator.accepts(input, schema: schema))
    }
    precondition(!ToolInputValidator.accepts(0, schema: ["enum": [false]]))
    precondition(!ToolInputValidator.accepts("x", schema: ["$ref": "remote"] ))
    precondition(!ToolInputValidator.accepts("x", schema: ["pattern": ".*"]))
    precondition(!ToolInputValidator.accepts([1, 2], schema: ["type": "array", "maxItems": 1]))
    precondition(ToolInputValidator.accepts(NSNull(), schema: ["type": ["string", "null"]]))
    var registry = AIToolRegistry()
    var definition = AIToolDefinition(id: "memora:lookup", name: "lookup", summary: "", inputSchema: try JSONSerialization.data(withJSONObject: schema),
      provider: .memora, requiredPermissions: ["read"], risk: .read, isAvailable: true, isEnabled: true)
    precondition(registry.register(definition))
    precondition(!registry.register(definition))
    precondition(registry.permits("lookup", arguments: ["query": "q"]))
    precondition(!registry.permits("unknown", arguments: [:]))
    definition.isEnabled = false
    registry.tools[definition.id] = definition
    precondition(!registry.permits("lookup", arguments: ["query": "q"]))
    for ending in ["\n\n", "\r\n\r\n"] {
      let notification = Data(("data: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/message\"}" + ending).utf8)
      precondition(MCPEventStream.isBoundary(notification))
      precondition(MCPEventStream.requestID(MCPEventStream.payload(notification)!) == nil)
      let response = Data(("data: {\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{}}" + ending).utf8)
      let request = Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#.utf8)
      precondition(MCPEventStream.requestID(MCPEventStream.payload(response)!) == MCPEventStream.requestID(request))
    }
    precondition(MCPEventStream.payload(Data(": heartbeat\n\n".utf8)) == nil)
    let old = Data(#"{"id":"00000000-0000-0000-0000-000000000001","name":"old","url":"https://example.com/mcp","isEnabled":true}"#.utf8)
    let restored = try JSONDecoder().decode(MCPServerConfig.self, from: old)
    precondition(restored.oauth == nil && restored.reviewedEndpoint == nil && restored.hasUsageCharges == nil && restored.approvedReadToolFingerprints == nil)
    let first = MCPTool(serverID: restored.id, serverName: "old", name: "a.b", summary: "read", inputSchema: Data("{}".utf8), isReadOnly: true)
    var second = first; second.name = "a_b"
    precondition(first.agentName != second.agentName && first.agentName.count <= 64)
    second = first; second.summary = "changed"
    precondition(first.fingerprint != second.fingerprint)
    for address in ["127.0.0.1", "10.1.2.3", "169.254.1.2", "172.16.1.2", "192.168.1.1", "100.64.0.1", "::1", "fe80::1", "fd00::1", "::ffff:127.0.0.1", "2001:db8::1", "2002:7f00:1::"] { precondition(!MCPPublicAddressPolicy.isPublic(address)) }
    for address in ["8.8.8.8", "1.1.1.1", "2606:4700:4700::1111"] { precondition(MCPPublicAddressPolicy.isPublic(address)) }
    precondition(MemoraSkill.context(for: "旅行", disabled: ["travel-plan"], budget: 300).isEmpty)
    precondition(!MemoraSkill.context(for: "旅行", disabled: [], budget: 300).isEmpty)
    precondition(MemoraSkill.context(for: "hello", disabled: [], budget: 300).isEmpty)
    precondition(MemoraSkill.bundled.allSatisfy { $0.skillMarkdown.hasPrefix("---\nname:") })
    let unconfigured: any IntegrationProvider = ComposioProvider()
    do { _ = try await unconfigured.tools(); preconditionFailure("unconfigured backend advertised tools") }
    catch IntegrationConnectionError.backendNotConfigured {}
    do { _ = try await unconfigured.execute(definition, arguments: Data("{}".utf8)); preconditionFailure("unconfigured backend executed") }
    catch IntegrationConnectionError.backendNotConfigured {}
    let lookup = MCPDNSLookup()
    lookup.finish(false)
    let cancelled = await withCheckedContinuation { lookup.install($0) }
    precondition(!cancelled)
    lookup.finish(true)
    let completed = MCPDNSLookup()
    let success = await withCheckedContinuation { continuation in
      completed.install(continuation)
      completed.finish(true)
      completed.finish(false)
    }
    precondition(success)
    print("ToolIntegrationChecks: passed (schema, registry, disabled/unknown tools, SSE IDs/CRLF, legacy config, namespace/fingerprint)")
  }
}
