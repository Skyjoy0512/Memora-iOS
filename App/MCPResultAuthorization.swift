import Foundation

/// Never persisted: external results remain usable only by their original run.
@MainActor
struct MCPResultAuthorization {
  var context: MCPAgentExecutionContext
  var server: MCPServerConfig
  var credentialRevision: UUID?
  var tokenFingerprint: String
  var tool: MCPTool

  func isCurrent(in model: MemoraModel) -> Bool {
    context.bindingIsCurrent(in: model) && model.mcpServerIsEnabled(server) &&
      model.mcpServers.contains(server) && model.mcpCredentialRevisions[server.id] == credentialRevision &&
      AIRecordFingerprint.make(KeychainStore.string(forKey: server.tokenAccount)) == tokenFingerprint &&
      model.activeMCPTools[tool.agentName]?.fingerprint == tool.fingerprint
  }
}
