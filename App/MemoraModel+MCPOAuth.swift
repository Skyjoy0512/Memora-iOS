import Foundation

extension MemoraModel {
  func hasMCPOAuthCredential(_ server: MCPServerConfig) -> Bool {
    guard let settings = server.oauth,
          let identity = try? MCPOAuthPolicy.identity(endpoint: server.url, settings: settings),
          let raw = KeychainStore.string(forKey: server.oauthAccount),
          let credential = try? JSONDecoder().decode(MCPOAuthCredential.self, from: Data(raw.utf8)) else { return false }
    return credential.identity == identity
  }

  func authorizeMCPServer(_ snapshot: MCPServerConfig, browser: MCPOAuthBrowser) async throws {
    guard mcpServers.contains(snapshot) else { throw MCPOAuthError.configuration }
    let revision = mcpCredentialRevisions[snapshot.id]
    let credential = try await browser.authorize(snapshot)
    try Task.checkCancellation()
    guard revision == mcpCredentialRevisions[snapshot.id], mcpServers.contains(snapshot) else { throw MCPOAuthError.reauthentication }
    let value = String(decoding: try JSONEncoder().encode(credential), as: UTF8.self)
    guard KeychainStore.set(value, forKey: snapshot.oauthAccount) else { throw MCPOAuthError.storage }
    mcpCredentialRevisions[snapshot.id] = UUID()
    if let index = mcpServers.firstIndex(where: { $0.id == snapshot.id }) {
      mcpServers[index].reviewedEndpoint = nil
      mcpServers[index].approvedReadToolFingerprints = nil
    }
    await MCPClient.shared.forget(snapshot.id)
  }

  func disconnectMCPOAuth(_ id: UUID) throws {
    guard let index = mcpServers.firstIndex(where: { $0.id == id }) else { return }
    guard KeychainStore.set(nil, forKey: mcpServers[index].oauthAccount) else { throw MCPOAuthError.storage }
    mcpCredentialRevisions[id] = UUID()
    mcpServers[index].reviewedEndpoint = nil
    mcpServers[index].approvedReadToolFingerprints = nil
    activeMCPTools = activeMCPTools.filter { $0.value.serverID != id }
    Task { await MCPOAuthClient.shared.cancel(id); await MCPClient.shared.forget(id) }
  }
}
