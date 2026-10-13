import Foundation

@main
struct MCPOAuthChecks {
  static func main() throws {
    let settings = MCPOAuthSettings(clientID: "public-client", authorizationURL: "https://auth.example.com/authorize",
      tokenURL: "https://auth.example.com/token", scopes: "read:notes read:files")
    let normalized = try MCPOAuthPolicy.validated(settings)
    precondition(normalized.scopes == "read:files read:notes")
    let identity = try MCPOAuthPolicy.identity(endpoint: "https://mcp.example.com/", settings: settings)
    var changed = settings; changed.clientID = "another-client"
    let changedIdentity = try MCPOAuthPolicy.identity(endpoint: "https://mcp.example.com/", settings: changed)
    precondition(changedIdentity != identity)
    let otherIdentity = try MCPOAuthPolicy.identity(endpoint: "https://other.example.com/", settings: settings)
    precondition(otherIdentity != identity)
    for url in ["http://example.com/auth", "https://127.0.0.1/auth", "https://example.local/auth", "https://user:pass@example.com/auth", "https://example.com/auth?token=x", "https://other.example.com/token"] {
      changed = settings; changed.tokenURL = url
      do { _ = try MCPOAuthPolicy.validated(changed); preconditionFailure("unsafe auth endpoint") } catch {}
    }
    for scopes in ["", "read\nwrite", "read\\write", "read\"write", "読取"] {
      changed = settings; changed.scopes = scopes
      do { _ = try MCPOAuthPolicy.validated(changed); preconditionFailure("unsafe scopes") } catch {}
    }
    let callback = URL(string: "memora://oauth/mcp?state=expected&code=fixture")!
    let code = try MCPOAuthPolicy.callbackCode(callback, state: "expected")
    precondition(code == "fixture")
    for raw in ["memora://oauth/mcp?state=wrong&code=fixture", "memora://oauth/other?state=expected&code=fixture",
      "other://oauth/mcp?state=expected&code=fixture", "memora://oauth/mcp?state=expected&state=bad&code=fixture",
      "memora://oauth/mcp?state=expected&code=a&code=b", "memora://oauth/mcp?state=expected&error=denied",
      "memora://oauth/mcp?state=expected&code=fixture#fragment"] {
      do { _ = try MCPOAuthPolicy.callbackCode(URL(string: raw)!, state: "expected"); preconditionFailure("unsafe callback") } catch {}
    }
    let granted: Set<String> = ["read:notes"]
    let first = try MCPOAuthCredential.decodeResponse(Data(#"{"access_token":"fixture-access","token_type":"Bearer","expires_in":3600,"refresh_token":"fixture-refresh","scope":"read:notes"}"#.utf8), identity: identity, requestedScopes: granted, now: Date(timeIntervalSince1970: 0))
    precondition(first.expiresAt == Date(timeIntervalSince1970: 3600))
    let restored = try JSONDecoder().decode(MCPOAuthCredential.self, from: JSONEncoder().encode(first))
    precondition(restored.identity == identity && restored.refreshToken == first.refreshToken && restored.scopes == first.scopes)
    let renewed = try MCPOAuthCredential.decodeResponse(Data(#"{"access_token":"rotated","token_type":"bearer","expires_in":3600}"#.utf8), identity: identity, requestedScopes: granted, previous: first)
    precondition(renewed.refreshToken == first.refreshToken && renewed.scopes == granted)
    for raw in [#"{"access_token":"x","token_type":"bearer","expires_in":true}"#,
      #"{"access_token":"x","token_type":"bearer","expires_in":-1}"#,
      #"{"access_token":"x","token_type":"bearer","expires_in":3600,"scope":"write:notes"}"#,
      #"{"access_token":"x","token_type":"mac","expires_in":3600}"#,
      #"{"access_token":"bad\ntoken","token_type":"bearer","expires_in":3600}"#,
      #"{"access_token":"x","token_type":"bearer","expires_in":3600,"error":"invalid_grant"}"#] {
      do { _ = try MCPOAuthCredential.decodeResponse(Data(raw.utf8), identity: identity, requestedScopes: granted); preconditionFailure("unsafe credential") } catch {}
    }
    let form = String(decoding: MCPOAuthPolicy.form(["code": "x&injected=y", "client_id": "public"]), as: UTF8.self)
    precondition(form.contains("x%26injected%3Dy") && !form.contains("x&injected"))
    print("MCPOAuthChecks: passed (endpoint/scope validation, identity binding, callback/CSRF duplicates, expiry, refresh rotation, privilege escalation, form encoding)")
  }
}
